-- redis.replicate_commands();

local exists_key      = KEYS[1]
local grabbed_key     = KEYS[2]
local available_key   = KEYS[3]
local version_key     = KEYS[4]
local exists_token    = ARGV[1]
local resource_count  = tonumber(ARGV[2])
local expiration      = tonumber(ARGV[3])
local api_version     = ARGV[4]
local token           = redis.call('getset', exists_key, exists_token)

local current_token

local function current_time()
  local time = redis.call('time')
  local s = time[1]
  local ms = time[2]
  local number = tonumber((s .. '.' .. ms))

  return number
end
if token then
  if token == api_version then
    if not redis.call('get', version_key) then
      redis.call('set', version_key, api_version)
      return 0
    end
  end

  return 1
else
  redis.call('expire', exists_key, 10)
  redis.call('del', grabbed_key)
  redis.call('del', available_key)

  local index = 0
  repeat
    redis.call('rpush', available_key, index)
    index = index + 1
  until index >= resource_count

  redis.call('set', version_key, api_version)
  redis.call('persist', exists_key)

  if expiration then
    redis.call('expire', available_key, expiration)
    redis.call('expire', exists_key, expiration)
    redis.call('expire', version_key, expiration)
  end

  return 0
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

if not timeout or timeout > 0 then
  -- passing timeout 0 to blpop causes it to block
  local value
  if timeout then
    value = timeout
  else
    value = 0
  end

  _key, current_token = redis.call('blpop', available_key, value)
else
  current_token = conn.lpop(available_key)
end

if not current_token then
  return 0
end

redis.call('hset', grabbed_key, current_token, current_time)

return current_token;
