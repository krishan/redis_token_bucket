# RedisTokenBucket

A [Token Bucket](https://en.wikipedia.org/wiki/Token_bucket) rate limiting implementation in Ruby using a Redis backend.

Features:
* Lightweight and efficient
  * Uses a single Redis key per bucket
  * Buckets are automatically created when first used
  * Buckets are automatically removed when no longer used
* Fast and concurrency safe
  * Each operation uses just a single network roundtrip to Redis
  * Charging tokens is done with all-or-nothing semantics
* Computed continuously
  * Token values (rate, size, current level, cost) use floating point numbers
  * Bucket level is computed with microsecond precision
* Powerful and flexible
  * Ability to charge multiple buckets with arbitrary token amounts at once
  * Ability to "reserve" tokens and to create "token debt"

Redis version 3.2 or newer is needed.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'redis_token_bucket'
```

## Usage

Basic rate limiting:

```ruby
require 'redis'
require 'redis_token_bucket'

# create connection to redis server
# details see: https://github.com/redis/redis-rb/
redis = Redis.new

# create a limiter instance which uses the redis connection
limiter = RedisTokenBucket.limiter(redis)

# define the bucket
bucket = {
  key: "RedisKeyForMyBucket",
  rate: 100,
  size: 1000,
}

# charge 10 tokens to the bucket
success, level = limiter.charge(bucket, 10)

# check if charging was successful
if success
  # rate limiter permits request
  call_my_business_logic
else
  # rate limiter denies request
  raise "Rate Limit exceeded. Increase you calm!"
end

# print the resulting level of tokens in the bucket
puts "The current level of tokens in my bucket: #{level}"

```

Reading the current level of tokens of a bucket:

```ruby
puts "Current level of tokens: #{limiter.read_level(bucket)}"
```

Charging multiple buckets at once:

```ruby
long_bucket = {
  key: "RedisKeyForLongBucket",
  rate: 100,
  size: 10000
}

short_bucket = {
  key: "RedisKeyForShortBucket",
  rate: 1000,
  size: 3000
}

success, levels = limiter.batch_charge(
  [long_bucket, 1],
  [short_bucket, 1]
)

puts "The current level of tokens in bucket short: #{levels[short_bucket[:key]]}"
puts "The current level of tokens in bucket long: #{levels[long_bucket[:key]]}"

if success
  # rate limiter permits request (all buckets were charged)
  call_my_business_logic
else
  # rate limiter denies request (none of the buckets was charged)
  raise "Rate Limit exceeded. Increase you calm!"
end
```

Reading the current level of tokens from multiple buckets:

```ruby
levels = limiter.read_levels(short_bucket, long_bucket)

puts "The current level of tokens in bucket short: #{levels[short_bucket[:key]]}"
puts "The current level of tokens in bucket long: #{levels[long_bucket[:key]]}"
```

Advanced: Bucket with Reserved Tokens

```ruby
# this reserves the last 10 tokens,
# i.e. charging will fail if it would result in less than 10 tokens

RedisTokenBucket.charge(bucket, 1, {limit: 10})

# also possible with batch_charge
RedisTokenBucket.batch_charge(
  [short_bucket, 1, {limit: 10}],
  [long_bucket, 2, {limit: 5}],
)
```

Advanced: Bucket with Token Debt

```ruby
# this allows up to 10 "negative" tokens
# i.e. charging will only fail if it would result in less than -10 tokens
RedisTokenBucket.charge(bucket, 1, {limit: -10})
```

## Development

After checking out the repo, run `bundle` to install dependencies.

Use `bundle exec rspec` to run tests.

Use `bundle exec ruby demo.rb` to run a demo.

## Contributors

Original author: Kristian Hanekamp
