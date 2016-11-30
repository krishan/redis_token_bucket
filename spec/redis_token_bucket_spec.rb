require 'redis'
require 'spec_helper'

describe RedisTokenBucket do

  let(:small_key) { random_key }
  let(:big_key) { random_key }

  let(:small_bucket) {{ rate: 2, size: 10,  key: small_key }}
  let(:big_bucket) {{ rate: 1, size: 100, key: big_key }}

  let(:buckets) { [small_bucket, big_bucket] }

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
    expect(limiter.read_levels(*buckets)).to eq({ small_key => 10, big_key => 100 })
  end

  it 'refills the bucket at the given rate, up to size' do
    _, levels = limiter.batch_charge([small_bucket, 10], [big_bucket, 10])

    levels = limiter.read_levels(*buckets)
    expect(levels).to eq({ small_key => 0, big_key => 90 })

    time_passes(2)

    levels = limiter.read_levels(*buckets)
    expect(levels).to eq({ small_key => 4, big_key => 92 })

    time_passes(4)

    levels = limiter.read_levels(*buckets)
    expect(levels).to eq({ small_key => 10, big_key => 96 })
  end

  it 'can handle floating-point values' do
    bucket = { rate: 0.1, size: 0.5, key: random_key }

    precision = 0.0000001

    level = limiter.read_level(bucket)
    expect(level).to be_within(precision).of(0.5)

    limiter.charge(bucket, 0.45)
    level = limiter.read_level(bucket)
    expect(level).to be_within(precision).of(0.05)

    time_passes(0.01)

    level = limiter.read_level(bucket)
    expect(level).to be_within(precision).of(0.051)
  end

  it 'stores each bucket under the given redis key' do
    _, levels = limiter.batch_charge([small_bucket, 10], [big_bucket, 10])
    expect(levels).to eq({ small_key => 0, big_key => 90 })

    # deleting a key should lead to the bucket being full again
    redis.del(small_key)

    levels = limiter.read_levels(*buckets)
    expect(levels).to eq({ small_key => 10, big_key => 90 })
  end

  it 'expires the redis key once the bucket is full again' do
    _, levels = limiter.batch_charge([small_bucket, 10], [big_bucket, 10])
    expect(levels).to eq({ small_key => 0, big_key => 90 })

    ttl = redis.ttl(small_key)
    expect(ttl).to be > 0
    expect(ttl).to be <= 5

    ttl = redis.ttl(big_key)
    expect(ttl).to be > 0
    expect(ttl).to be <= 10
  end

  it 'uses actual time from redis server' do
    # use limiter without faked time
    limiter = RedisTokenBucket::Limiter.new(Redis.connect)

    _, level = limiter.charge(small_bucket, 10)
    expect(level).to eq(0)

    sleep 0.01

    expect(limiter.read_level(small_bucket)).to be >= 0.01
  end

  it 'is resilient against empty script cache' do
    levels = limiter.read_levels(*buckets)
    expect(levels).to eq({ small_key => 10, big_key => 100 })

    redis.script(:flush)

    levels = limiter.read_levels(*buckets)
    expect(levels).to eq({ small_key => 10, big_key => 100 })
  end

  it 'is resilient against clock anomalies' do
    limiter.charge(small_bucket, 1)
    expect(limiter.read_level(small_bucket)).to eq(9)

    time_passes(-1)
    expect(limiter.read_level(small_bucket)).to eq(9)

    time_passes(1)
    expect(limiter.read_level(small_bucket)).to eq(9)

    time_passes(1)
    expect(limiter.read_level(small_bucket)).to eq(10)
  end

  it 'sucessfully charges tokens iff every bucket has sufficient tokens' do
    success, levels = limiter.batch_charge([small_bucket, 7], [big_bucket, 7])
    expect(success).to be_truthy
    expect(levels).to eq({ small_key => 3, big_key => 93 })

    success, levels = limiter.batch_charge([small_bucket, 7], [big_bucket, 7])
    expect(success).to be_falsey
    expect(levels).to eq({ small_key => 3, big_key => 93 })

    time_passes(1)

    success, levels = limiter.batch_charge([small_bucket, 7], [big_bucket, 7])
    expect(success).to be_falsey
    expect(levels).to eq({ small_key => 5, big_key => 94 })

    time_passes(1)

    success, levels = limiter.batch_charge([small_bucket, 7], [big_bucket, 7])
    expect(success).to be_truthy
    expect(levels).to eq({ small_key => 0, big_key => 88 })
  end

  it 'reserves tokens, when using a positive limit' do
    success, levels = limiter.batch_charge([small_bucket, 5, limit: 5], [big_bucket, 5])
    expect(success).to be_truthy
    expect(levels).to eq({ small_key => 5, big_key => 95 })

    success, levels = limiter.batch_charge([small_bucket, 1, limit: 5], [big_bucket, 1])
    expect(success).to be_falsey
    expect(levels).to eq({ small_key => 5, big_key => 95 })

    success, level = limiter.charge(small_bucket, 1, limit: 5)
    expect(success).to be_falsey
    expect(level).to eq(5)
  end

  it 'allows token debt, when using a negative limit' do
    success, levels = limiter.batch_charge([small_bucket, 15, limit: -5], [big_bucket, 15])
    expect(success).to be_truthy
    expect(levels).to eq({ small_key => -5, big_key => 85 })

    success, levels = limiter.batch_charge([small_bucket, 1, limit: -5], [big_bucket, 1])
    expect(success).to be_falsey
    expect(levels).to eq({ small_key => -5, big_key => 85 })
  end

  it 'refuses to charge an amount of zero or smaller' do
    expect { limiter.charge(small_bucket, 0) }.to raise_error(ArgumentError)
    expect { limiter.charge(small_bucket, -1) }.to raise_error(ArgumentError)
  end

  it 'offers a convenience syntax to charge a single bucket' do
    success, level = limiter.charge(small_bucket, 5)
    expect(success).to be_truthy
    expect(level).to eq(5)

    level = limiter.read_level(small_bucket)
    expect(level).to eq(5)
  end
end
