-- redis.replicate_commands();

local exists_key      = KEYS[1]
local grabbed_key     = KEYS[2]
local available_key   = KEYS[3]
local current_jid     = ARGV[1]
local expiration      = tonumber(ARGV[2])
local persisted_token = redis.call('GETSET', exists_key, current_jid)

if persisted_token then
  return persisted_token
else
  redis.call('EXPIRE', exists_key, 10)
  redis.call('DEL', grabbed_key)
  redis.call('DEL', available_key)
  redis.call('RPUSH', available_key, current_jid)

  redis.call('PERSIST', exists_key)

  if expiration then
    redis.log(redis.LOG_DEBUG, "exists_or_create.lua - expiring locks in : " .. expiration)
    redis.call('EXPIRE', available_key, expiration)
    redis.call('EXPIRE', exists_key, expiration)
  end

  return current_jid
end
