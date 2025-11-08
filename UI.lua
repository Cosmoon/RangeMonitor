local ADDON, ns = ...
local UI = {}
ns.UI = UI

local Range = ns.Range

-------------------------------------------------------
-- Apply font size (title + names together)
-------------------------------------------------------
function UI:ApplyFont()
  if not self.frame then return end
  local base, _, flags = GameFontNormal:GetFont()
  local size = (self.db and self.db.fontSize) or 12

  -- create / reuse
  if not self.fontBody then self.fontBody = CreateFont("RangeMonitorFontBody") end
  if not self.fontTitle then self.fontTitle = CreateFont("RangeMonitorFontTitle") end

  self.fontBody:SetFont(base, size, flags)
  self.fontTitle:SetFont(base, size, flags)

  if self.title then self.title:SetFontObject(self.fontTitle) end
  if self.lines then
    for _, fs in ipairs(self.lines) do
      fs:SetFontObject(self.fontBody)
    end
  end
end

-------------------------------------------------------
-- Initialization
-------------------------------------------------------
function UI:Init(db)
  self.db = db
  self.lines = {}

  -- frame
  local f = CreateFrame("Frame", "RangeMonitorFrame", UIParent)
  self.frame = f
  f:SetPoint("CENTER")
  f:SetSize(220, 260)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
  f:SetScript("OnDragStop",  function(frame) frame:StopMovingOrSizing() end)

  -- title
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -4)
  title:SetText("RangeMonitor: 0y  0/0")
  self.title = title

  -- close button (top-right)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function() f:Hide() end)

  -- names
  for i = 1, 15 do
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -24 - (i-1)*14)
    fs:SetText("")
    self.lines[i] = fs
  end

  -- apply initial font size to title + names
  self:ApplyFont()

  f:Hide()
end

-------------------------------------------------------
-- Refresh display
-- Color rules (X = threshold):
--  dist <= X        → red
--  X < dist <= X+4  → orange
--  dist > X+5       → hidden
-------------------------------------------------------
function UI:Refresh()
  if not self.frame or not self.frame:IsShown() then return end

  local threshold = self.db.threshold or 10
  local units = IsInRaid() and ns._raidUnits or ns._partyUnits
  local list = {}
  local inCount, total = 0, 0

  for _, u in ipairs(units) do
    if UnitExists(u) and not UnitIsUnit(u, "player") then
      total = total + 1
      local name = GetUnitName(u, true) or UnitName(u)
      local dist = Range:GetExactRange(u) or Range:GetApproxRange(u)
      if dist then
        if dist <= threshold then
          inCount = inCount + 1
          list[#list+1] = { name = name, dist = dist, color = "red" }
        elseif dist <= threshold + 4 then
          list[#list+1] = { name = name, dist = dist, color = "orange" }
        end
      end
    end
  end

  table.sort(list, function(a,b) return a.dist < b.dist end)

  -- Title text + state color
  if self.title then
    self.title:SetText(("RangeMonitor: %dy  %d/%d"):format(threshold, inCount, total))
    if not self.db.sendEnabled then
      self.title:SetTextColor(0.7, 0.7, 0.7)          -- grey: receive-only
    elseif ns.Range and ns.Range.localUnavailable then
      self.title:SetTextColor(1, 0.85, 0.0)           -- yellow: proxy mode
    else
      self.title:SetTextColor(1, 1, 1)                -- white: normal
    end
  end

  -- lines
  for i, fs in ipairs(self.lines) do
    local data = list[i]
    if data then
      local colorCode = (data.color == "red") and "|cffff0000" or "|cffffa500"
      fs:SetText(colorCode .. data.name .. " – " .. string.format("%.1f", data.dist) .. "y|r")
      fs:Show()
    else
      fs:Hide()
    end
  end

  -- Debug overlay (if you already added it earlier)
  if self.debugText and self.db.debug then
    local comms = ns.Comms
    local totalSenders = 0
    if comms and comms._receiveCache then
      for _ in pairs(comms._receiveCache) do totalSenders = totalSenders + 1 end
    end
    local totalRaid = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
    self.debugText:SetText(("Sync: %d/%d"):format(totalSenders, totalRaid))
    self.debugText:Show()
  elseif self.debugText then
    self.debugText:Hide()
  end
end
