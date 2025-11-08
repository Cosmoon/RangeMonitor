local ADDON, ns = ...
local Range = {}
ns.Range = Range

local Probes = ns.Probes

Range._cache = {}

function Range:UpdateBuckets()
  wipe(self._cache)
  local units = IsInRaid() and ns._raidUnits or ns._partyUnits
  local badCount, totalCount = 0, 0

  for _, u in ipairs(units) do
    if UnitExists(u) and not UnitIsUnit(u, "player") then
      totalCount = totalCount + 1
      local lower, upper, localEstimate = 0, 40, nil
      if ns.Probes and ns.Probes.GetRangeBracket then
        lower, upper, localEstimate = ns.Probes:GetRangeBracket(u)
      end

      local entry = {
        lower = lower,
        upper = upper,
        hasLocal = localEstimate ~= nil,
      }

      local localDist = localEstimate
      if not localDist then
        if lower and upper then
          localDist = (lower + upper) / 2
        elseif upper then
          localDist = upper
        elseif lower then
          localDist = lower
        end
      end

      entry.localEstimate = localDist
      if not entry.hasLocal or not localDist or localDist >= 39 then
        badCount = badCount + 1
      end

      local merged
      if ns.Comms and ns.Comms.GetMergedDistance then
        merged = ns.Comms:GetMergedDistance(u, localDist)
      end

      entry.estimate = merged or localDist or 999
      entry.mergedEstimate = merged

      self._cache[u] = entry
    end
  end

  self.localUnavailable = (totalCount > 0 and badCount >= totalCount * 0.9)
end

function Range:GetExactRange(unit)
  local data = self._cache[unit]
  return data and data.estimate
end

function Range:GetApproxRange(unit)
  local data = self._cache[unit]
  return data and data.estimate
end

function Range:IsInsideThreshold(unit, threshold)
  local data = self._cache[unit]
  if not data then return false end
  if data.upper and data.upper <= threshold then return true end
  if data.lower and data.lower > threshold then return false end
  return data.estimate and data.estimate <= threshold
end
