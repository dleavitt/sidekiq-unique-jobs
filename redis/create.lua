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
