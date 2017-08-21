-- redis.replicate_commands();

local exists_key           = KEYS[1]
local grabbed_key          = KEYS[2]
local available_key        = KEYS[3]
local version_key          = KEYS[4]
local lock_key             = KEYS[5]

local expires_in           = tonumber(ARGV[1])
local stale_client_timeout = tonumber(ARGV[2])
local expiration           = tonumber(ARGV[3])

local function current_time()
  local time = redis.call('time')
  local s = time[1]
  local ms = time[2]
  local number = tonumber((s .. '.' .. ms))

  return number
end

local hgetall = function (key)
  local bulk = redis.call('HGETALL', key)
  local result = {}
  local nextkey
  for i, v in ipairs(bulk) do
    if i % 2 == 1 then
      nextkey = v
    else
      result[nextkey] = v
    end
  end
  return result
end

local cached_current_time = current_time()
local my_lock_expires_at = cached_current_time + expires_in + 1

if not redis.call('SETNX', lock_key, my_lock_expires_at) then
  -- Check if expired
  local other_lock_expires_at = tonumber(redis.call('GET', lock_key))

  if other_lock_expires_at < cached_current_time then
    local old_expires_at = tonumber(redis.call('GETSET', lock_key, my_lock_expires_at))

    -- Check if another client started cleanup yet. If not,
    -- then we now have the lock.
    if not old_expires_at == other_lock_expires_at then
      return 0
    end
  end
end

local keys = hgetall(grabbed_key)
for key, locked_at in pairs(keys) do
  local timed_out_at = tonumber(locked_at) + stale_client_timeout

  if timed_out_at < current_time() then
    redis.call('HDEL', grabbed_key, key)
    redis.call('LPUSH', available_key, key)

    if expiration then
      redis.call('EXPIRE', available_key, expiration)
      redis.call('EXPIRE', exists_key, expiration)
      redis.call('EXPIRE', version_key, expiration)
    end
  end
end

-- Make sure not to delete the lock in case someone else already expired
-- our lock, with one second in between to account for some lag.
if my_lock_expires_at > (current_time() - 1) then
  redis.call('DEL', lock_key)
end

return 1
