-- redis.replicate_commands();

local exists_key      = KEYS[1]
local grabbed_key     = KEYS[2]
local available_key   = KEYS[3]
local version_key     = KEYS[4]
local exists_token    = ARGV[1]
local resource_count  = tonumber(ARGV[2])
local expiration      = tonumber(ARGV[3])
local api_version     = ARGV[4]
local persisted_token = redis.call('GETSET', exists_key, exists_token)

if persisted_token then
  if not redis.call('GET', version_key) then
    redis.call('SET', version_key, api_version)
  end

  return persisted_token
else
  redis.call('EXPIRE', exists_key, 10)
  redis.call('DEL', grabbed_key)
  redis.call('DEL', available_key)

  local index = 0
  repeat
    redis.call('RPUSH', available_key, index)
    index = index + 1
  until index >= resource_count

  redis.call('SET', version_key, api_version)
  redis.call('PERSIST', exists_key)

  if expiration then
    redis.call('EXPIRE', available_key, expiration)
    redis.call('EXPIRE', exists_key, expiration)
    redis.call('EXPIRE', version_key, expiration)
  end

  return exists_token
end
