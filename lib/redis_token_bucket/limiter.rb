module RedisTokenBucket
class Limiter
  def initialize(redis, clock = nil)
    @redis = redis
    @clock = clock
  end

  # charges `amount` tokens to the specified `bucket`.
  #
  # charging only happens if the bucket has sufficient tokens.
  # the level of "sufficient tokens" can be adjusted by passing in option[:limit]
  #
  # returns a tuple (= Array with two elements) containing
  # `success:boolean` and `level:Numeric`
  def charge(bucket, amount, options = nil)
    success, levels = batch_charge([bucket, amount, options])

    return success, levels[bucket[:key]]
  end

  # performs several bucket charge operations in batch.
  #
  # each operation is passed in as an Array, containing the parameters
  # for `batch`.
  #
  # charging only happens if all buckets have sufficient tokens.
  # the charges are done transactionally, so either all buckets are charged or none.
  #
  # returns a tuple (= Array with two elements) containing
  # `success:boolean` and `levels:Hash<String, Numeric>`
  # where `levels` is a hash from bucket keys to bucket levels.
  def batch_charge(*charges)
    charges.each do |(bucket, amount, options)|
      unless amount > 0
        message = "tried to charge #{amount}, needs to be Numeric and > 0"
        raise ArgumentError, message
      end
    end

    run_script(charges)
  end

  # returns the current level of tokens in the specified `bucket`.
  def read_level(bucket)
    read_levels(bucket)[bucket[:key]]
  end

  # reports the current level of tokens for each of the specified `buckets`.
  # returns the levels as a Hash from bucket keys to bucket levels.
  def read_levels(*buckets)
    _, levels = run_script(buckets.map { |bucket| [bucket, 0] })

    levels
  end

  private

  def run_script(charges)
    props = charges.map(&method(:props_for_charge)).flatten
    time = @clock.call if @clock

    argv = [time] + props
    keys = charges.map { |(bucket, _, _)| bucket[:key] }

    success, levels = eval_script(:keys => keys, :argv => argv)

    levels_as_hash = {}
    levels.each_with_index do |level, index|
      levels_as_hash[keys[index]] = level.to_f
    end

    [success > 0, levels_as_hash]
  end

  def props_for_charge(charge)
    bucket, amount, options = charge

    [bucket[:rate], bucket[:size], amount, options ? options[:limit] : nil]
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
