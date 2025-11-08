local ADDON, ns = ...
local Comms = {}
ns.Comms = Comms

local prefix = ns.C and ns.C.PREFIX or "RANGEMON"
C_ChatInfo.RegisterAddonMessagePrefix(prefix)

Comms._lastSend = 0
Comms._receiveCache = {}

-------------------------------------------------------
-- Base64 (Classic-safe, no bitwise)
-------------------------------------------------------
local B64 = {}
do
  local enc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  B64.enc = enc

  local function num_to_6bit(n)
    return math.floor(n / 2^18) % 64,
           math.floor(n / 2^12) % 64,
           math.floor(n / 2^6)  % 64,
           n % 64
  end

  function B64.encode(bytes)
    local t = {}
    for i = 1, #bytes, 3 do
      local a = bytes:byte(i) or 0
      local b = bytes:byte(i + 1) or 0
      local c = bytes:byte(i + 2) or 0
      local n = a * 65536 + b * 256 + c
      local n1, n2, n3, n4 = num_to_6bit(n)
      t[#t + 1] = enc:sub(n1 + 1, n1 + 1)
      t[#t + 1] = enc:sub(n2 + 1, n2 + 1)
      t[#t + 1] = (i + 1 <= #bytes) and enc:sub(n3 + 1, n3 + 1) or "="
      t[#t + 1] = (i + 2 <= #bytes) and enc:sub(n4 + 1, n4 + 1) or "="
    end
    return table.concat(t)
  end

  function B64.decode(str)
    str = str:gsub("[^%w%+/=]", "")
    local dec = {}
    for i = 1, 64 do dec[enc:sub(i, i)] = i - 1 end
    dec["="] = 0
    local t = {}
    for i = 1, #str, 4 do
      local a = dec[str:sub(i, i)] or 0
      local b = dec[str:sub(i + 1, i + 1)] or 0
      local c = dec[str:sub(i + 2, i + 2)] or 0
      local d = dec[str:sub(i + 3, i + 3)] or 0
      local n = a * 262144 + b * 4096 + c * 64 + d
      local x = math.floor(n / 65536) % 256
      local y = math.floor(n / 256) % 256
      local z = n % 256
      t[#t + 1] = string.char(x, y, z)
    end
    local out = table.concat(t)
    local pad = 0
    if str:sub(-2) == "==" then pad = 2 elseif str:sub(-1) == "=" then pad = 1 end
    return (pad > 0) and out:sub(1, -pad - 1) or out
  end
end

-------------------------------------------------------
-- Small helpers
-------------------------------------------------------
local function unitIndex(unit)
  if IsInRaid() then
    local idx = tonumber(unit:match("^raid(%d+)$") or "")
    return idx and math.min(math.max(idx, 1), 40) or nil
  else
    if unit == "player" then return 0 end
    local idx = tonumber(unit:match("^party(%d+)$") or "")
    return idx and math.min(math.max(idx, 1), 4) or nil
  end
end

local function nameFromIndex(idx)
  if IsInRaid() then
    if idx >= 1 and idx <= 40 then
      local u = "raid" .. idx
      if UnitExists(u) then return UnitName(u) end
    end
  else
    if idx == 0 then return UnitName("player") end
    if idx >= 1 and idx <= 4 then
      local u = "party" .. idx
      if UnitExists(u) then return UnitName(u) end
    end
  end
  return nil
end

-------------------------------------------------------
-- Init
-------------------------------------------------------
function Comms:Init(db)
  self.db = db
end

-------------------------------------------------------
-- Broadcast (compressed)
-------------------------------------------------------
function Comms:Broadcast(elapsed)
  if self.db and self.db.sendEnabled == false then return end
  self._lastSend = (self._lastSend or 0) + elapsed
  if self._lastSend < 1.0 then return end
  self._lastSend = 0
  if not IsInGroup() then return end

  local cache = ns.Range._cache or {}
  local maxShow = (RangeMonitorDB and RangeMonitorDB.threshold) or 10
  local maxSend = maxShow + 5
  local bytes = {}

  -- 0 = party, 1 = raid, +2 if local data unavailable
  local headerMode = IsInRaid() and 1 or 0
  if ns.Range and ns.Range.localUnavailable then
    headerMode = headerMode + 2
  end
  bytes[#bytes + 1] = string.char(headerMode)

  local count = 0
  for unit, data in pairs(cache) do
    local dist = data and data.estimate
    if dist and dist <= maxSend then
      local idx = unitIndex(unit)
      if idx then
        local q = math.min(255, math.max(0, math.floor(dist * 10 + 0.5)))
        bytes[#bytes + 1] = string.char(math.floor(idx % 256))
        bytes[#bytes + 1] = string.char(math.floor(q % 256))
        count = count + 1
      end
    end
  end

  if count > 0 then
    local payload = B64.encode(table.concat(bytes))
    local chan = IsInRaid() and "RAID" or "PARTY"
    C_ChatInfo.SendAddonMessage(prefix, payload, chan)
    if self.db and self.db.debug then
      print(("|cff33ff99RangeMonitor|r sent %d entries (%s)"):format(count, chan))
    end
  end
end

-------------------------------------------------------
-- Receive
-------------------------------------------------------
function Comms:OnMessage(sender, msg)
  if sender == UnitName("player") then return end
  local raw = B64.decode(msg or "")
  if not raw or #raw < 1 then return end

  local mode = raw:byte(1) or 0
  local senderBlind = (mode >= 2)
  if senderBlind then mode = mode - 2 end

  local now = GetTime()
  self._receiveCache[sender] = self._receiveCache[sender] or {}
  local i = 2
  while i + 1 <= #raw do
    local idx = raw:byte(i)
    local q = raw:byte(i + 1)
    local name = nameFromIndex(idx)
    if name then
      local dist = q / 10.0
      self._receiveCache[sender][name] = { dist = dist, time = now }
    end
    i = i + 2
  end

  if senderBlind and self.db and self.db.debug then
    print("|cffaaaa00RangeMonitor:|r " .. sender .. " in proxy mode (no local data)")
  end

  if self.db and self.db.debug then
    local c = 0
    for _ in pairs(self._receiveCache[sender]) do c = c + 1 end
    print(("|cff33ff99RangeMonitor|r recv %d from %s"):format(c, sender))
  end
end

-------------------------------------------------------
-- Merge distances
-------------------------------------------------------
function Comms:GetMergedDistance(unit, localHint)
  local name = ns._unitToName[unit]
  if not name then return localHint end
  local now = GetTime()
  local total, count = 0, 0

  for _, data in pairs(self._receiveCache) do
    local e = data[name]
    if e and (now - e.time) < 5 then
      total = total + e.dist
      count = count + 1
    end
  end

  if count > 0 then
    local avg = total / count
    return localHint and ((avg + localHint) / 2) or avg
  end
  return localHint
end
