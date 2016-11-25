# TODO each bucket with separate "minimum", allows to model both "reserved" and "debt/force"
# TODO integrative test using the "main.rb"
module RedisTokenBucket
class Limiter
  def initialize(redis, clock = nil)
    @redis = redis
    @clock = clock
  end

  # tries to charges `amount` tokens to each of the specified `buckets`.
  #
  # charging only happens if all buckets have sufficient tokens.
  # the charge is done transactionally, so either all buckets are charged or none.
  #
  # returns a tuple (= Array with two elements) containing
  # `success:boolean` and `levels:Hash<String, Numeric>`
  def charge(buckets, amount)
    run_script(buckets, amount)
  end

  # reports the current level of tokens for each of the specified `buckets`.
  # returns the levels as a Hash from bucket names to levels
  def read_levels(buckets)
    run_script(buckets, 0)[1]
  end

  private

  def run_script(buckets, amount)
    bucket_names = buckets.keys
    keys = bucket_names.map { |name| buckets[name][:key] }
    props = bucket_names.map { |name| [buckets[name][:rate], buckets[name][:size]] }.flatten

    time = @clock.call if @clock

    # TODO evalsha
    success, levels, debug = eval_script(:keys => keys, :argv => [time, amount] + props)

    levels_as_hash = {}
    levels.each_with_index do |level, index|
      levels_as_hash[bucket_names[index]] = level.to_f
    end

    [success > 0, levels_as_hash]
  end

  def eval_script(options)
    retries = 0

    begin
      @redis.evalsha(script_sha, options)
    rescue Redis::CommandError => e
      if retries > 0
        raise
      end

      @@script_sha = nil

      retries = 1
      retry
    end
  end

  def script_sha
    @@script_sha ||= @redis.script(:load, script_code)
  end

  def script_code
    @@script ||= File.read(File.expand_path("../limiter.lua", __FILE__))
  end
end
end
