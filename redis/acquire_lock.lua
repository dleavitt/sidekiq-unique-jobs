-- redis.replicate_commands();

local unique_key = KEYS[1]
local job_id     = ARGV[1]
local expires    = ARGV[2]
local stored_jid = redis.call('GET', unique_key)

if stored_jid then
  if stored_jid == job_id then
    return 1
  else
    return 0
  end
end

if redis.call('SET', unique_key, job_id, 'NX', 'EX', expires) then
  redis.call('HSETNX', 'uniquejobs', job_id, unique_key)
  return 1
else
  return 0
end
