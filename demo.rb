require "redis_token_bucket"
require "concurrent"
require "redis"
require "securerandom"

puts <<-EOS
  The script attempts to make a huge number of requests against the rate limiter.
  Each second, the number of requests accepted and denied by the rate limiter is printed.

  You should see the following pattern:
  * briefly, a burst of requests is permitted
  * then the 'short' buckets starts limiting to 1000 requests per second
  * after a few seconds, the 'long' buckets starts limiting to 100 requests per second

EOS

def random_key
  "RedisTokenBucket:demo:#{SecureRandom.hex}"
end

buckets = {
  long: {
    key: random_key,
    rate: 100,
    size: 10000
  },
  short: {
    key: random_key,
    rate: 1000,
    size: 3000
  }
}

consumed = Concurrent::Atom.new(0)

rejected = {}
buckets.each { |name, bucket| rejected[name] = Concurrent::Atom.new(0) }

def increase(atom)
  atom.swap { |before| before + 1 }
end

def reset(atom)
  last = nil

  atom.swap do |before|
    last = before

    0
  end

  last
end

NUM_FORKS = 1
NUM_THREADS_PER_FORK = 10

child_processes = NUM_FORKS.times.map do
  Process.fork do

    # each fork has an independent output thread
    output = Thread.new do
      last_output = 0
      while true
        now = Time.now.to_i

        if last_output < now
          denied_stats = rejected.map { |name, atom| "#{name}: #{reset(atom)}" }
          puts "Accepted: #{reset(consumed)} / Denied: #{denied_stats}"

          last_output = now
        end

        sleep 0.001
      end
    end

    # and a number of worker threads, charging tokens
    workers = NUM_THREADS_PER_FORK.times.map do |i|
      Thread.new do
        begin
          limiter = RedisTokenBucket.limiter(Redis.new)

          while true
            success, levels = limiter.charge(buckets, 1)

            if success
              increase(consumed)
            else
              levels.map do |name, level|
                increase(rejected[name]) if level < 1
              end
            end
          end
        rescue e
          puts "ERROR"
          puts e
        end
      end
    end

    output.join
    workers.join
  end
end

child_processes.map { |pid| Process.waitpid(pid) }
