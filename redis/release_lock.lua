-- redis.replicate_commands();

local unique_key = KEYS[1]
local job_id     = ARGV[1]
local stored_jid = redis.call('GET', unique_key)

if stored_jid then
  if stored_jid == job_id or stored_jid == '2' then
    redis.call('DEL', unique_key)
    redis.call('HDEL', 'uniquejobs', job_id)
    return 1
  else
    return 0
  end
else
  return -1
end

