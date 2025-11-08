local ADDON, ns = ...
RangeMonitor = ns

-------------------------------------------------------
-- Constants
-------------------------------------------------------
local C = {}
ns.C = C

C.PREFIX = "RANGEMON"       -- unified prefix for comms
C.UPDATE_RATE = 0.3
C.DEFAULTS = {
  enabled = true,
  threshold = 5,
  debug = false,
  sendEnabled = true,
  fontSize = 12,             -- NEW: title + names scale together
}

-------------------------------------------------------
-- Saved vars + helpers
-------------------------------------------------------
local db

local function deepcopy(tbl)
  if type(tbl) ~= "table" then return tbl end
  local t = {}
  for k,v in pairs(tbl) do t[k] = deepcopy(v) end
  return t
end

local function ensureDB()
  if type(RangeMonitorDB) ~= "table" then RangeMonitorDB = deepcopy(C.DEFAULTS) end
  db = RangeMonitorDB
  for k,v in pairs(C.DEFAULTS) do
    if db[k] == nil then db[k] = deepcopy(v) end
  end
end

-------------------------------------------------------
-- Group lists
-------------------------------------------------------
ns._partyUnits, ns._raidUnits, ns._unitToName, ns._nameToUnit = {}, {}, {}, {}

local function RebuildUnitLists()
  wipe(ns._partyUnits); wipe(ns._raidUnits); wipe(ns._unitToName); wipe(ns._nameToUnit)
  if IsInRaid() then
    for i=1,40 do
      local unit = "raid"..i
      if UnitExists(unit) then
        local name = UnitName(unit)
        if name then
          table.insert(ns._raidUnits, unit)
          ns._unitToName[unit] = name
          ns._nameToUnit[name] = unit
        end
      end
    end
  else
    table.insert(ns._partyUnits, "player")
    for i=1,4 do
      local unit = "party"..i
      if UnitExists(unit) then table.insert(ns._partyUnits, unit) end
    end
    for _,unit in ipairs(ns._partyUnits) do
      local name = UnitName(unit)
      if name then ns._unitToName[unit] = name; ns._nameToUnit[name] = unit end
    end
  end
end

-------------------------------------------------------
-- Help text
-------------------------------------------------------
local function PrintHelp()
  print("|cff33ff99RangeMonitor commands:|r")
  print("  /rangemonitor <yards>  or  /rm <yards>    |cffffffffSet range and show frame|r")
  print("  /rangemonitor show     or  /rm show       |cffffffffShow the frame|r")
  print("  /rangemonitor hide     or  /rm hide       |cffffffffHide the frame|r")
  print("  /rangemonitor toggle   or  /rm toggle     |cffffffffToggle the frame|r")
  print("  /rangemonitor size <10|12|14|16|18>  or  /rm size <10|12|14|16|18>  |cffffffffSet font size (title+names)|r")
  print("  /rangemonitor debug    or  /rm debug      |cffffffffToggle debug overlay and prints|r")
  print("  /rangemonitor send     or  /rm send       |cffffffffToggle sending (receive-only mode)|r")
end

-------------------------------------------------------
-- Slash commands
-------------------------------------------------------
local function SlashHandler(msg)
  msg = (msg and msg:match("^%s*(.-)%s*$"):lower()) or ""
  if msg == "" then
    PrintHelp()
    return
  end

  -- size command
  local sizeArg = msg:match("^size%s+(%d+)$")
  if sizeArg then
    local s = tonumber(sizeArg)
    local allowed = { [10]=true, [12]=true, [14]=true, [16]=true, [18]=true }
    if allowed[s] then
      db.fontSize = s
      if ns.UI and ns.UI.ApplyFont then ns.UI:ApplyFont() end
      print(("|cff33ff99RangeMonitor|r font size set to %d"):format(s))
    else
      print("|cffff0000RangeMonitor: invalid size.|r Use 10, 12, 14, 16, or 18.")
    end
    return
  end

  -- debug toggle
  if msg == "debug" then
    db.debug = not db.debug
    print("|cff33ff99RangeMonitor|r debug mode: " .. (db.debug and "|cffff0000ON|r" or "|cff00ff00OFF|r"))
    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
    return
  end

  -- send toggle (receive-only)
  if msg == "send" then
    db.sendEnabled = not db.sendEnabled
    if db.sendEnabled then
      print("|cff33ff99RangeMonitor|r: Sending |cff00ff00ENABLED|r (full sync mode).")
    else
      print("|cff33ff99RangeMonitor|r: Sending |cffff0000DISABLED|r (receive-only mode).")
    end
    return
  end

  -- visibility
  if msg == "show" then
    if ns.UI and ns.UI.frame then ns.UI.frame:Show(); ns.UI:Refresh() end
    return
  elseif msg == "hide" then
    if ns.UI and ns.UI.frame then ns.UI.frame:Hide() end
    return
  elseif msg == "toggle" then
    if ns.UI and ns.UI.frame then
      if ns.UI.frame:IsShown() then ns.UI.frame:Hide() else ns.UI.frame:Show(); ns.UI:Refresh() end
    end
    return
  end

  -- numeric argument: set threshold & show
  local n = tonumber(msg)
  if n then
    db.threshold = n
    print(("RangeMonitor: threshold set to %d yards"):format(n))
    if ns.UI and ns.UI.frame then ns.UI.frame:Show(); ns.UI:Refresh() end
    return
  end

  -- unknown → help
  PrintHelp()
end

local function RegisterSlashes()
  SlashCmdList["RANGEMONITOR"] = SlashHandler
  SLASH_RANGEMONITOR1 = "/rangemonitor"

  SlashCmdList["RM"] = SlashHandler
  SLASH_RM1 = "/rm"
end

-------------------------------------------------------
-- Event handling
-------------------------------------------------------
local f = CreateFrame("Frame")
ns._eventFrame = f
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("CHAT_MSG_ADDON")
C_ChatInfo.RegisterAddonMessagePrefix(C.PREFIX)

f:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local addon = ...
    if addon == "RangeMonitor" then
      ensureDB()
      RebuildUnitLists()
      RegisterSlashes()
      if ns.UI and ns.UI.Init then ns.UI:Init(db) end
      if ns.Comms and ns.Comms.Init then ns.Comms:Init(db) end
      print("|cff33ff99RangeMonitor|r loaded. Type /rangemonitor or /rm for help.")
    end

  elseif event == "PLAYER_LOGIN" then
    RegisterSlashes()

  elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
    RebuildUnitLists()

  elseif event == "CHAT_MSG_ADDON" then
    local prefix, msg, channel, sender = ...
    if prefix == C.PREFIX and ns.Comms and ns.Comms.OnMessage then
      ns.Comms:OnMessage(sender, msg)
    end
  end
end)

-------------------------------------------------------
-- Update loop
-------------------------------------------------------
local elapsedTotal = 0
f:SetScript("OnUpdate", function(_, elapsed)
  elapsedTotal = elapsedTotal + elapsed
  if elapsedTotal >= C.UPDATE_RATE then
    elapsedTotal = 0
    if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then
      if ns.Range and ns.Range.UpdateBuckets then ns.Range:UpdateBuckets() end
      if ns.UI.Refresh then ns.UI:Refresh() end
    end
  end
  if ns.Comms and ns.Comms.Broadcast then
    ns.Comms:Broadcast(elapsed)
  end
end)
