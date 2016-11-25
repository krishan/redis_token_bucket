require "redis_token_bucket/version"
require "redis_token_bucket/limiter"

module RedisTokenBucket

  def self.limiter(redis)
    Limiter.new(redis)
  end

end
