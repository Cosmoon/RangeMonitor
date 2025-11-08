local ADDON, ns = ...
local Probes = {}
ns.Probes = Probes

-- Map spellIDs → range; resolve names via GetSpellInfo (locale-safe).
local CLASS_SPELLS = {
  PRIEST = {
    { id = 2061, range = 40 },  -- Flash Heal
    { id = 17,   range = 30 },  -- Power Word: Shield
  },
  DRUID = {
    { id = 774,  range = 40 },  -- Rejuvenation
    { id = 1126, range = 30 },  -- Mark of the Wild
  },
  PALADIN = {
    { id = 19750, range = 40 }, -- Flash of Light
    { id = 20217, range = 30 }, -- Blessing of Kings
  },
  SHAMAN = {
    { id = 8004,  range = 40 }, -- Lesser Healing Wave
    { id = 526,   range = 30 }, -- Cure Poison (ally)
  },
  MAGE = {
    { id = 1459,  range = 30 }, -- Arcane Intellect
  },
  WARLOCK = {
    { id = 5697,  range = 30 }, -- Unending Breath
  },
  HUNTER = {
    -- Hunters: few ally singles; rely mostly on interact fallbacks
  },
  WARRIOR = {
    -- No friendly singles; rely on interact fallbacks
  },
  ROGUE = {
    -- Few ally singles; rely on interact fallbacks
  },
}

-- Resolve spell names once (locale-safe)
local _, CLASS = UnitClass("player")
local RESOLVED = {}
do
  local list = CLASS_SPELLS[CLASS] or {}
  for _, p in ipairs(list) do
    local name = GetSpellInfo(p.id)
    if name then
      RESOLVED[#RESOLVED+1] = { name = name, range = p.range }
    end
  end
end

-----------------------------------------------------------------------
--  Cached universal items
-----------------------------------------------------------------------
Probes.bandageID, Probes.scrollID = nil, nil

local function IsBandage(name)
  return name and name:find("Bandage") and not name:find("Kit")
end

local function IsScroll(name)
  return name and name:find("^Scroll of")
end

-- Bag API compat (Dragonflight / Classic variants)
local GetBagNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetBagItemID   = (C_Container and C_Container.GetContainerItemID)   or GetContainerItemID
local NUM_BAG_SLOTS  = NUM_BAG_SLOTS or 4  -- classic default fallback

function Probes:ScanBags()
  self.bandageID, self.scrollID = nil, nil

  for bag = 0, NUM_BAG_SLOTS do
    local slots = GetBagNumSlots and GetBagNumSlots(bag) or 0
    for slot = 1, slots do
      local id = GetBagItemID and GetBagItemID(bag, slot)
      if id then
        -- Prefer fast Instant info if available
        local name
        if GetItemInfoInstant then
          local _, _, classID, subClassID = GetItemInfoInstant(id)
          -- Consumable=0; Bandage subclass is usually 7 in retail, but be lenient:
          if classID == 0 then
            name = GetItemInfo(id) -- lazy load name just once when needed
            if not self.bandageID and name and name:find("Bandage") and not name:find("Kit") then
              self.bandageID = id
            elseif not self.scrollID and name and name:find("^Scroll of") then
              self.scrollID = id
            end
          end
        else
          -- Fallback: name matching (Classic-safe)
          name = GetItemInfo(id)
          if name then
            if not self.bandageID and name:find("Bandage") and not name:find("Kit") then
              self.bandageID = id
            elseif not self.scrollID and name:find("^Scroll of") then
              self.scrollID = id
            end
          end
        end
      end

      if self.bandageID and self.scrollID then
        return
      end
    end
  end
end

-- Register bag events once
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:SetScript("OnEvent", function()
  Probes:ScanBags()
end)

-----------------------------------------------------------------------
--  Safe IsItemInRange wrapper
-----------------------------------------------------------------------
local function SafeItemInRange(itemID, unit)
  if not itemID then return nil end
  local ok, res = pcall(IsItemInRange, itemID, unit)
  return ok and res or nil
end

-----------------------------------------------------------------------
--  Range logic
-----------------------------------------------------------------------
function Probes:GetRangeBracket(unit)
  if not UnitExists(unit) then return nil end
  local lower, upper = 0, 40

  -- 1. class spells
  for _, p in ipairs(RESOLVED) do
    local r = IsSpellInRange(p.name, unit)
    if r == 1 then upper = math.min(upper, p.range)
    elseif r == 0 then lower = math.max(lower, p.range) end
  end

  -- 2. bandage (~15y)
  local band = SafeItemInRange(self.bandageID, unit)
  if band == 1 then upper = math.min(upper, 15)
  elseif band == 0 then lower = math.max(lower, 15) end

  -- 3. scroll (~30y)
  local scroll = SafeItemInRange(self.scrollID, unit)
  if scroll == 1 then upper = math.min(upper, 30)
  elseif scroll == 0 then lower = math.max(lower, 30) end

  -- 4. interact (duel ~10y, follow ~28y)
  local playerCombat = UnitAffectingCombat and UnitAffectingCombat("player")
  local unitCombat = UnitAffectingCombat and UnitAffectingCombat(unit)

  local duelInRange = CheckInteractDistance(unit, 3)
  if duelInRange then
    upper = math.min(upper, 10)
  elseif not (playerCombat or unitCombat) then
    -- When either player is in combat the duel check always fails. Treat it as
    -- "unknown" instead of forcing the lower bound above 10 yards so that we
    -- don't incorrectly mark close players as out of range mid-fight.
    lower = math.max(lower, 10)
  end

  local followInRange = CheckInteractDistance(unit, 4)
  if followInRange then
    upper = math.min(upper, 28)
  elseif not (playerCombat or unitCombat) then
    -- The follow distance also returns false during combat, so only push the
    -- lower bound when both players are free to interact.
    lower = math.max(lower, 28)
  end

  if upper < lower then upper = lower end
  return lower, upper, (lower + upper) / 2
end

function Probes:GetEstimate(unit)
  local _, _, e = self:GetRangeBracket(unit)
  return e or 40
end
