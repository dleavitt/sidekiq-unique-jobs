local exists_key      = KEYS[1]
local grabbed_key     = KEYS[2]
local available_key   = KEYS[3]
local version_key     = KEYS[4]
local exists_token    = ARGV[1]
local resource_count  = tonumber(ARGV[2])
local expiration      = tonumber(ARGV[3])
local api_version     = ARGV[4]
local token           = redis.pcall('getset', exists_key, exists_token)

if token then
  if token == api_version then
    if not redis.pcall('get', version_key) then
      redis.pcall('set', version_key, api_version)
      return 0
    end
  end

  return 1
else
  redis.pcall('expire', exists_key, 10)
  redis.pcall('del', grabbed_key)
  redis.pcall('del', available_key)

  local index = 0
  repeat
    redis.pcall('rpush', available_key, index)
    index = index + 1
  until index >= resource_count

  redis.pcall('set', version_key, api_version)
  redis.pcall('persist', exists_key)

  if expiration then
    redis.pcall('expire', available_key, expiration)
    redis.pcall('expire', exists_key, expiration)
    redis.pcall('expire', version_key, expiration)
  end

  return 0
end
