require 'redis'
require 'spec_helper'

describe RedisTokenBucket do

  let(:small_bucket_key) { random_key }
  let(:big_bucket_key) { random_key }

  let(:buckets) {{
      small: { rate: 2, size: 10,  key: small_bucket_key },
        big: { rate: 1, size: 100, key: big_bucket_key },
  }}

  let(:redis) { Redis.connect }

  let(:limiter) do
    RedisTokenBucket::Limiter.new(redis, proc { @fake_time })
  end

  before do
    @fake_time = 1480352223.522996
  end

  def random_key
    "RedisTokenBucket:specs:#{SecureRandom.hex}"
  end

  def time_passes(seconds)
    @fake_time += seconds
  end

  it 'has a version number' do
    expect(RedisTokenBucket::VERSION).not_to be nil
  end

  it 'initially fills buckets with tokens up to size' do
    expect(limiter.read_levels(buckets)).to eq({ small: 10, big: 100 })
  end

  it 'refills the bucket at the given rate, up to size' do
    _, levels = limiter.charge(buckets, 10)

    levels = limiter.read_levels(buckets)
    expect(levels).to eq({ small: 0, big: 90 })

    time_passes(2)

    levels = limiter.read_levels(buckets)
    expect(levels).to eq({ small: 4, big: 92 })

    time_passes(4)

    levels = limiter.read_levels(buckets)
    expect(levels).to eq({ small: 10, big: 96 })
  end

  it 'can handle floating-point values' do
    buckets = { one: { rate: 0.1, size: 0.5, key: random_key } }

    precision = 0.0000001

    levels = limiter.read_levels(buckets)
    expect(levels[:one]).to be_within(precision).of(0.5)

    limiter.charge(buckets, 0.45)
    levels = limiter.read_levels(buckets)
    expect(levels[:one]).to be_within(precision).of(0.05)

    time_passes(0.01)

    levels = limiter.read_levels(buckets)
    expect(levels[:one]).to be_within(precision).of(0.051)
  end

  it 'stores each bucket under the given redis key' do
    _, levels = limiter.charge(buckets, 10)
    expect(levels).to eq({ small: 0, big: 90 })

    # deleting a key should lead to the bucket being full again
    redis.del(small_bucket_key)

    levels = limiter.read_levels(buckets)
    expect(levels).to eq({ small: 10, big: 90 })
  end

  it 'expires the redis key once the bucket is full again' do
    _, levels = limiter.charge(buckets, 10)
    expect(levels).to eq({ small: 0, big: 90 })

    ttl = redis.ttl(small_bucket_key)
    expect(ttl).to be > 0
    expect(ttl).to be <= 5

    ttl = redis.ttl(big_bucket_key)
    expect(ttl).to be > 0
    expect(ttl).to be <= 10
  end

  it 'uses actual time from redis server' do
    # use limiter without faked time
    limiter = RedisTokenBucket::Limiter.new(Redis.connect)

    _, levels = limiter.charge(buckets, 10)
    expect(levels).to eq({ small: 0, big: 90 })

    sleep 0.01

    expect(limiter.read_levels(buckets)[:small]).to be >= 0.01
  end

  it 'is resilient against empty script cache' do
    levels = limiter.read_levels(buckets)
    expect(levels).to eq({ small: 10, big: 100 })

    redis.script(:flush)

    levels = limiter.read_levels(buckets)
    expect(levels).to eq({ small: 10, big: 100 })
  end

  it 'is resilient against clock anomalies' do
    limiter.charge(buckets, 1)
    expect(limiter.read_levels(buckets)).to eq({ small: 9, big: 99 })

    time_passes(-1)
    expect(limiter.read_levels(buckets)).to eq({ small: 9, big: 99 })

    time_passes(1)
    expect(limiter.read_levels(buckets)).to eq({ small: 9, big: 99 })

    time_passes(1)
    expect(limiter.read_levels(buckets)).to eq({ small: 10, big: 100 })
  end

  it 'sucessfully charges tokens iff every bucket has sufficient tokens' do
    success, levels = limiter.charge(buckets, 7)
    expect(success).to be_truthy
    expect(levels).to eq({ small: 3, big: 93 })

    success, levels = limiter.charge(buckets, 7)
    expect(success).to be_falsey
    expect(levels).to eq({ small: 3, big: 93 })

    time_passes(1)

    success, levels = limiter.charge(buckets, 7)
    expect(success).to be_falsey
    expect(levels).to eq({ small: 5, big: 94 })

    time_passes(1)

    success, levels = limiter.charge(buckets, 7)
    expect(success).to be_truthy
    expect(levels).to eq({ small: 0, big: 88 })
  end

  it 'reserves tokens, when using a positive limit' do
    buckets[:small][:limit] = 5

    success, levels = limiter.charge(buckets, 5)
    expect(success).to be_truthy
    expect(levels).to eq({ small: 5, big: 95 })

    success, levels = limiter.charge(buckets, 1)
    expect(success).to be_falsey
    expect(levels).to eq({ small: 5, big: 95 })
  end

  it 'allows token debt, when using a negative limit' do
    buckets[:small][:limit] = -5

    success, levels = limiter.charge(buckets, 15)
    expect(success).to be_truthy
    expect(levels).to eq({ small: -5, big: 85 })

    success, levels = limiter.charge(buckets, 1)
    expect(success).to be_falsey
    expect(levels).to eq({ small: -5, big: 85 })
  end

  it 'refuses to charge an amount of zero or smaller' do
    expect { limiter.charge(buckets, 0) }.to raise_error(ArgumentError)
    expect { limiter.charge(buckets, -1) }.to raise_error(ArgumentError)
  end
end
