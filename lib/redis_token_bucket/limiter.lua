redis.replicate_commands()
local injected_time = tonumber(ARGV[1])
local redis_time = redis.call('time')
local local_time = redis_time[1] + 0.000001 * redis_time[2]

local now = injected_time or local_time

local current_bucket_levels = {}
local new_bucket_levels = {}
local timeouts = {}
local exceeded = false

for key_index, key in ipairs(KEYS) do
  local arg_index = key_index * 4 - 2
  local rate = tonumber(ARGV[arg_index])
  local size = tonumber(ARGV[arg_index + 1])
  local amount = tonumber(ARGV[arg_index + 2])

  local bucket = redis.call('hmget', key, 'time', 'level')
  local last_time = tonumber(bucket[1]) or now
  local before_level = tonumber(bucket[2]) or size

  local elapsed = math.max(0, now - last_time)
  local gained = rate * elapsed

  local current_level = math.min(size, before_level + gained)

  current_bucket_levels[key_index] = current_level

  if amount > 0 then
    local limit = tonumber(ARGV[arg_index + 3]) or 0

    local new_level = current_level - amount
    new_bucket_levels[key_index] = new_level

    local seconds_to_full = (size - new_level) / rate
    timeouts[key_index] = seconds_to_full

    if new_level < limit then
      exceeded = true
    end
  end
end

local levels_to_report
local charged

if exceeded or #new_bucket_levels == 0 then
  levels_to_report = current_bucket_levels
  charged = 0
else
  levels_to_report = new_bucket_levels
  charged = 1

  for key_index, key in ipairs(KEYS) do
    local new_level = new_bucket_levels[key_index]
    local timeout = timeouts[key_index]

    redis.call('hmset', key,
      'time', string.format("%.16g", now),
      'level', string.format("%.16g", new_level)
      )

    redis.call('expire', key, math.ceil(timeout))
  end
end

local formatted_levels = {}
for index, value in ipairs(levels_to_report) do
  formatted_levels[index] = string.format("%.16g", value)
end

return {charged, formatted_levels}
