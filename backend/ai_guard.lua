-- KEYS:
-- 1 ip_rate_key
-- 2 device_rate_key (can be empty string if none)
-- 3 user_quota_key
-- 4 org_quota_key (can be empty string if none)
-- 5 burst_key
--
-- ARGV:
-- 1 ip_rpm_limit
-- 2 device_rpm_limit
-- 3 user_daily_limit
-- 4 org_daily_limit
-- 5 credits
-- 6 minute_ttl
-- 7 day_ttl
-- 8 burst_cap
-- 9 burst_refill_per_sec
-- 10 now_epoch

local ip_key = KEYS[1]
local device_key = KEYS[2]
local user_quota_key = KEYS[3]
local org_quota_key = KEYS[4]
local burst_key = KEYS[5]

local ip_rpm_limit = tonumber(ARGV[1])
local device_rpm_limit = tonumber(ARGV[2])
local user_daily_limit = tonumber(ARGV[3])
local org_daily_limit = tonumber(ARGV[4])
local credits = tonumber(ARGV[5])
local minute_ttl = tonumber(ARGV[6])
local day_ttl = tonumber(ARGV[7])
local burst_cap = tonumber(ARGV[8])
local burst_refill = tonumber(ARGV[9])
local now = tonumber(ARGV[10])

-- 1) IP rate
local ip_count = redis.call("INCR", ip_key)
if ip_count == 1 then redis.call("EXPIRE", ip_key, minute_ttl) end
if ip_count > ip_rpm_limit then
  return {0, "ip_rate"}
end

-- 2) Device rate (optional)
if device_key and device_key ~= "" then
  local d_count = redis.call("INCR", device_key)
  if d_count == 1 then redis.call("EXPIRE", device_key, minute_ttl) end
  if d_count > device_rpm_limit then
    return {0, "device_rate"}
  end
end

-- 3) Burst token bucket: store as "tokens|ts"
local state = redis.call("GET", burst_key)
local tokens = burst_cap
local ts = now
if state then
  local sep = string.find(state, "|")
  if sep then
    tokens = tonumber(string.sub(state, 1, sep-1)) or burst_cap
    ts = tonumber(string.sub(state, sep+1)) or now
  end
end

local elapsed = now - ts
if elapsed < 0 then elapsed = 0 end
tokens = math.min(burst_cap, tokens + elapsed * burst_refill)

if tokens < 1 then
  return {0, "burst"}
end
tokens = tokens - 1
redis.call("SET", burst_key, tostring(tokens) .. "|" .. tostring(now), "EX", 60)

-- 4) Daily quota (user)
local used_u = tonumber(redis.call("GET", user_quota_key) or "0")
if used_u + credits > user_daily_limit then
  return {0, "user_quota", used_u}
end

-- 5) Daily quota (org optional)
if org_quota_key and org_quota_key ~= "" and org_daily_limit > 0 then
  local used_o = tonumber(redis.call("GET", org_quota_key) or "0")
  if used_o + credits > org_daily_limit then
    return {0, "org_quota", used_o}
  end
end

-- 6) Consume quota
redis.call("INCRBY", user_quota_key, credits)
redis.call("EXPIRE", user_quota_key, day_ttl)

if org_quota_key and org_quota_key ~= "" and org_daily_limit > 0 then
  redis.call("INCRBY", org_quota_key, credits)
  redis.call("EXPIRE", org_quota_key, day_ttl)
end

return {1, "ok", used_u + credits}
