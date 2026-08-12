local addonName, TW = ...

local CreateFrame = CreateFrame
local GetTime = GetTime
local format = string.format
local AuraUtil = AuraUtil
local C_UnitAuras = C_UnitAuras
local MAX_TANKS = TW.MAX_TANKS

-- ============================================================
-- SECRET-VALUE HELPERS (Midnight 12.0)
-- See https://github.com/enderneko/Cell/pull/457 for the canonical patterns.
-- Rule: never do arithmetic, comparison, or table-indexing with a secret
-- value — gate first, fall back to safe defaults otherwise.
-- ============================================================
local issecretvalue = _G.issecretvalue
local function isSecret(v)
    if issecretvalue then return issecretvalue(v) end
    return false
end

-- HARMFUL aura iteration. We skip AuraUtil.ForEachAura entirely because in
-- 12.0 it throws on raid units and the C-side error appears to leak taint
-- past pcall. C_UnitAuras.GetAuraDataByIndex is the safe path on retail.
-- On MoP Classic 5.5 (where C_UnitAuras doesn't exist) we fall back to
-- the legacy positional UnitAura(unit, i, "HARMFUL"), synthesizing an
-- aura table compatible with the rest of the code (passesFilter,
-- getStacks, the icon/timer paths). Secret-value paths are no-ops on
-- Classic since secrets are a 12.0 concept — `isSecret` returns false
-- when issecretvalue isn't defined.
-- DandersFrames / Cell pattern: AuraUtil.ForEachAura is the only path
-- that accepts the specialized HARMFUL|RAID / RAID_IN_COMBAT / IMPORTANT
-- / DISPELLABLE filter strings (C_UnitAuras.GetAuraDataByIndex ignores
-- the pipe suffix). Some boss debuffs on friendly units in 12.0 ONLY
-- appear under those specialized slots, never under plain "HARMFUL" —
-- so we scan each filter, dedupe by auraInstanceID, and emit each
-- unique aura once via the callback.
-- DandersFrames pattern: event-driven per-unit aura cache. UNIT_AURA
-- delivers an updateInfo payload that includes addedAuras (full
-- auraData blob) BEFORE GetAuraSlots can be polled for them — in 12.0
-- some auras are filtered out of slot enumeration but still ride in
-- the event payload. We cache by auraInstanceID, populate via the
-- event handler (TW.HandleUnitAura), and iterate the cache instead of
-- doing a live scan.
TW._auraCache = TW._auraCache or {}

local function cacheEntry(unit)
    if not TW._auraCache[unit] then
        TW._auraCache[unit] = { byID = {}, order = {} }
    end
    return TW._auraCache[unit]
end

local function cacheAdd(entry, aura, instId)
    if not entry.byID[instId] then
        entry.order[#entry.order + 1] = instId
    end
    entry.byID[instId] = aura
end

local function cacheRemove(entry, instId)
    if entry.byID[instId] then
        entry.byID[instId] = nil
        for i, oid in ipairs(entry.order) do
            if oid == instId then table.remove(entry.order, i); break end
        end
    end
end

-- Full GetAuraSlots scan — used to bootstrap the cache when we don't
-- yet have one for a unit (first-access) or when the event payload
-- says isFullUpdate (Blizzard signal that the cache is stale).
local function rescanFull(unit)
    local entry = cacheEntry(unit)
    wipe(entry.byID)
    wipe(entry.order)
    -- Primary path: GetAuraSlots + GetAuraDataBySlot. Fast but in
    -- 12.0 it occasionally returns 0 slots for secret-tagged hostile-
    -- sourced auras even when the auras DO exist (observed in raid:
    -- GetAuraSlots returns 0 while GetAuraDataByIndex sees 2).
    if C_UnitAuras and C_UnitAuras.GetAuraSlots
       and C_UnitAuras.GetAuraDataBySlot then
        local returns = { pcall(C_UnitAuras.GetAuraSlots, unit, "HARMFUL", 40) }
        if returns[1] then
            for i = 3, #returns do
                local slot = returns[i]
                local ok, aura = pcall(C_UnitAuras.GetAuraDataBySlot, unit, slot)
                if ok and aura then
                    local instId
                    pcall(function() instId = aura.auraInstanceID end)
                    -- Accept any non-nil instId including secret-tagged
                    -- numbers. The render path consumes instId only via
                    -- secret-safe C functions (SetUnitBuffByAuraInstanceID,
                    -- GetAuraDuration, GetAuraApplicationDisplayCount)
                    -- which digest secrets natively. A strict
                    -- type=="number" check rejected boss debuffs whose
                    -- auraInstanceID got sealed by Blizzard in 12.0.
                    if instId ~= nil then
                        cacheAdd(entry, aura, instId)
                    end
                end
            end
        end
    end
    -- Fallback / supplement: GetAuraDataByIndex. Always runs to catch
    -- auras the slot enumeration missed. Dedup by auraInstanceID so
    -- we don't double-add anything from the slot path. /tankw auradebug
    -- showed in real raid combat that this is where the secret-tagged
    -- boss debuffs come through when GetAuraSlots returns nothing.
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
            if not ok or not aura then break end
            local instId
            pcall(function() instId = aura.auraInstanceID end)
            -- Same secret-instId tolerance as the slot path above.
            -- Dedup attempts entry.byID[instId] — if instId is secret,
            -- the lookup will miss (secret keys aren't reusable across
            -- queries) so we may double-add. cacheAdd checks duplicates
            -- by instId equality anyway, so the worst case is a single
            -- extra entry per secret aura, harmless for rendering.
            if instId ~= nil and not entry.byID[instId] then
                cacheAdd(entry, aura, instId)
            end
        end
    end
end

-- Public event handler — called from the OnEvent dispatcher in Tank.lua
-- on every UNIT_AURA for tank-frame units. Applies the delta when
-- updateInfo is present, full rescan otherwise.
function TW:HandleUnitAura(unit, updateInfo)
    if not unit then return end
    if not updateInfo or updateInfo.isFullUpdate then
        rescanFull(unit)
        return
    end
    local entry = cacheEntry(unit)
    if updateInfo.addedAuras then
        for _, aura in ipairs(updateInfo.addedAuras) do
            local instId
            pcall(function() instId = aura.auraInstanceID end)
            -- Accept any non-nil instId (secret-tagged included).
            if instId ~= nil then
                -- Categorize via IsAuraFilteredOutByInstanceID. The
                -- addedAuras payload is a FLAT list mixing helpful and
                -- harmful auras (auraData.isHarmful is secret on Midnight
                -- per the oUF reference, so we can't read it directly).
                -- DandersFrames pattern: test HELPFUL first — if the C
                -- function says "not filtered out by HELPFUL", it's a
                -- buff, REJECT. Else test HARMFUL — accept only on
                -- explicit confirmation. Default is REJECT (safer than
                -- the previous `isHarmful = true` fallback which leaked
                -- buffs into the cache when either check failed).
                -- Single HARMFUL truthy check. pcall'd because the C call
                -- can throw on secret-tagged instance IDs in 12.0 — a raw
                -- error would break this loop and skip every subsequent
                -- aura in the payload. ok=false default rejects buffs;
                -- a successful call returns true when filtered out (= buff
                -- or unrelated) so `not filteredOut` is falsy and we skip.
                if _IsAuraFilteredOut then
                    local ok, filteredOut = pcall(_IsAuraFilteredOut, unit, instId, "HARMFUL")
                    if ok and not filteredOut then
                        cacheAdd(entry, aura, instId)
                    end
                end
            end
        end
    end
    if updateInfo.updatedAuraInstanceIDs then
        for _, id in ipairs(updateInfo.updatedAuraInstanceIDs) do
            if entry.byID[id] and C_UnitAuras
               and C_UnitAuras.GetAuraDataByAuraInstanceID then
                local ok, fresh = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
                if ok and fresh then entry.byID[id] = fresh end
            end
        end
    end
    if updateInfo.removedAuraInstanceIDs then
        for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do
            cacheRemove(entry, id)
        end
    end
end

-- Wipe cache for a unit (or all units when unit is nil). Called on
-- roster changes so stale entries from old tanks don't linger.
function TW:WipeAuraCache(unit)
    if unit then
        TW._auraCache[unit] = nil
    else
        wipe(TW._auraCache)
    end
end

local function iterHarmful(unit, max, callback, mode)
    -- mode is accepted for API symmetry; cache always holds HARMFUL.
    -- Read from cache; populate via rescanFull if first access.
    local entry = TW._auraCache[unit]
    if not entry then
        rescanFull(unit)
        entry = TW._auraCache[unit]
    end
    if entry then
        -- Sort by expirationTime ascending so the most urgent debuffs
        -- (least time left) reach the renderer first. Permanent auras
        -- (expirationTime == 0) get pushed to the end via math.huge.
        -- DandersFrames' RebuildLegacySortedArrays equivalent.
        local sortable = {}
        for _, instId in ipairs(entry.order) do
            local aura = entry.byID[instId]
            if aura then
                local exp
                pcall(function() exp = aura.expirationTime end)
                local key
                if isSecret(exp) or type(exp) ~= "number" or exp == 0 then
                    key = math.huge
                else
                    key = exp
                end
                sortable[#sortable + 1] = { aura = aura, key = key }
            end
        end
        table.sort(sortable, function(a, b) return a.key < b.key end)
        local emitted = 0
        for _, item in ipairs(sortable) do
            if callback(item.aura, -1) then return "cache" end
            emitted = emitted + 1
            if emitted >= max then return "cache" end
        end
        return "cache"
    end
    -- Legacy fallbacks (Classic / pre-12.0 retail) bypass the cache.
    if C_UnitAuras and C_UnitAuras.GetAuraSlots and C_UnitAuras.GetAuraDataBySlot then
        local emitted = 0
        local returns = { pcall(C_UnitAuras.GetAuraSlots, unit, "HARMFUL", max) }
        if not returns[1] then return "GetAuraSlots-failed" end
        for i = 3, #returns do
            local slot = returns[i]
            local ok, aura = pcall(C_UnitAuras.GetAuraDataBySlot, unit, slot)
            if ok and aura then
                if callback(aura, -1) then break end
                emitted = emitted + 1
                if emitted >= max then break end
            end
        end
        return "GetAuraSlots+GetAuraDataBySlot"
    elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        -- Older retail builds without GetAuraSlots — indexed scan.
        for i = 1, max do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
            if not ok or not aura then break end
            local stop = callback(aura, i)
            if stop then break end
        end
        return "GetAuraDataByIndex"
    elseif _G.UnitAura then
        for i = 1, max do
            local name, icon, count, _, duration, expirationTime,
                  source, _, _, spellId, _, isBossDebuff =
                _G.UnitAura(unit, i, "HARMFUL")
            if not name then break end
            local aura = {
                name                     = name,
                icon                     = icon,
                applications             = count or 0,
                duration                 = duration,
                expirationTime           = expirationTime,
                sourceUnit               = source,
                spellId                  = spellId,
                isBossAura               = isBossDebuff and true or false,
                isFromPlayerOrPlayerPet  = (source == "player" or source == "pet"),
            }
            local stop = callback(aura, i)
            if stop then break end
        end
        return "UnitAura"
    end
    return nil
end

-- ============================================================
-- AURA BUTTON
-- ============================================================
local function CreateAuraButton(parent, index)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(28, 28); b:Hide()
    -- Tooltip on hover. We store the unit + harmful index when the aura
    -- is bound in UpdateAuras; SetUnitDebuff is secret-safe (Blizzard
    -- handles tainted aura data internally).
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        if self._testMode then
            -- In test mode there's no real aura to query; show a stub.
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self._testName or "Test debuff", 1, 0.4, 0.4)
            GameTooltip:AddLine("Test mode", 0.7, 0.7, 0.7)
            local db = TW.GetDB and TW:GetDB()
            if db and db.showSpellIDInTooltip ~= false then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cffaaaaaaspellID|r |cffffff009999|r (test)")
            end
            GameTooltip:Show()
            return
        end
        local unit = self._unit
        local idx  = self._harmfulIndex
        local instId = self._auraInstanceID
        if not unit then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- Prefer the modern secret-safe API; fall back to the legacy
        -- index-based one when no instance ID is available.
        if instId ~= nil
           and GameTooltip.SetUnitBuffByAuraInstanceID then
            pcall(GameTooltip.SetUnitBuffByAuraInstanceID, GameTooltip,
                  unit, instId, "HARMFUL")
        elseif idx and idx > 0 and GameTooltip.SetUnitDebuff then
            pcall(GameTooltip.SetUnitDebuff, GameTooltip, unit, idx)
        end
        -- spellID line is appended by the global TooltipDataProcessor
        -- hook in TankWatch.lua — works for every tooltip in the UI
        -- (BuffFrame, action bars, /cast preview, etc.), not just ours.
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(b)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon = icon

    local border = b:CreateTexture(nil, "OVERLAY", nil, 1)
    border:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 0.9)
    border:SetDrawLayer("BACKGROUND")
    b.border = border

    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(b)
    cd:SetHideCountdownNumbers(true)
    cd:SetDrawEdge(false); cd:SetDrawSwipe(true)
    b.cd = cd

    -- TIMER: HUGE, centered, yellow with thick outline + shadow. The
    -- prominent number tells the tank/healer how many seconds before the
    -- next tick / next cooldown decision.
    local timer = cd:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
    timer:SetPoint("CENTER", b, "CENTER", 0, 0)
    timer:SetTextColor(1, 0.9, 0.1)
    timer:SetShadowColor(0, 0, 0, 1)
    timer:SetShadowOffset(1, -1)
    timer:SetDrawLayer("OVERLAY", 7)
    b.timer = timer

    -- STACK COUNT: small, bottom-right corner of the icon, white with
    -- shadow. Secondary info next to the prominent timer.
    local stacks = cd:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    stacks:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    stacks:SetJustifyH("RIGHT")
    stacks:SetTextColor(1, 1, 1)
    stacks:SetShadowColor(0, 0, 0, 1)
    stacks:SetShadowOffset(1, -1)
    stacks:SetDrawLayer("OVERLAY", 7)
    b.stacks = stacks

    b.index = index
    return b
end

local function ensurePool(frame, count)
    frame._auras = frame._auras or {}
    local created = false
    for i = 1, count do
        if not frame._auras[i] then
            frame._auras[i] = CreateAuraButton(frame, i)
            created = true
        end
    end
    for i = count + 1, #frame._auras do frame._auras[i]:Hide() end
    -- Newly created buttons start with the default NumberFontNormalHuge /
    -- NumberFontNormal — re-apply the configured font so they match the
    -- existing ones. Happens on first combat when the pool grows past
    -- whatever ApplyFonts saw at PLAYER_LOGIN.
    if created then
        if TW.ApplyFonts then TW:ApplyFonts() end
        -- Newly created buttons have no anchor — without an immediate
        -- LayoutAuras pass they fall back to the parent's top-left and
        -- appear in the wrong corner. ApplyLayout (which usually calls
        -- LayoutAuras) is gated by combat lockdown, so when the pool
        -- grows mid-combat the new buttons stay unanchored. Force a
        -- layout pass right here — LayoutAuras only touches the
        -- non-secure aura button frames, so it's safe in combat.
        if TW.LayoutAuras then TW.LayoutAuras(frame, TW:GetDB()) end
    end
end

local function formatTime(s)
    if s <= 0 then return "" end
    if s < 10 then return format("%.1f", s) end
    if s < 60 then return format("%d", s) end
    if s < 3600 then return format("%dm", math.floor(s / 60)) end
    return format("%dh", math.floor(s / 3600))
end

-- ============================================================
-- LAYOUT
-- ============================================================
local function justify(anchor)
    if anchor:find("LEFT") then return "LEFT"
    elseif anchor:find("RIGHT") then return "RIGHT"
    else return "CENTER" end
end

function TW.ApplyAuraTextLayout(b, db)
    if not b or not b.stacks or not b.timer then return end
    local sa = db.auraStackAnchor or "CENTER"
    b.stacks:ClearAllPoints()
    b.stacks:SetPoint(sa, b, sa, db.auraStackX or 0, db.auraStackY or 0)
    b.stacks:SetJustifyH(justify(sa))

    local ta = db.auraTimerAnchor or "BOTTOMRIGHT"
    b.timer:ClearAllPoints()
    b.timer:SetPoint(ta, b, ta, db.auraTimerX or -1, db.auraTimerY or 1)
    b.timer:SetJustifyH(justify(ta))
    if db.auraTimerShow == false then b.timer:Hide() else b.timer:Show() end
end

function TW.LayoutAuras(frame, db)
    if not db.showAuras then
        if frame._auras then
            for _, a in ipairs(frame._auras) do a:Hide() end
        end
        return
    end
    local maxCount = db.aurasMaxCount or 5
    ensurePool(frame, maxCount)

    local size = db.aurasSize or 28
    local spacing = db.aurasSpacing or 2
    local growX = db.aurasGrowX or "RIGHT"
    local anchor = db.aurasAnchor or "RIGHT"
    -- relPoint mirrors `anchor` so the icon sits OUTSIDE the frame on
    -- the chosen side, not overlapping it. RIGHT->LEFT, LEFT->RIGHT,
    -- TOP->BOTTOM, BOTTOM->TOP, corners flip LEFT<->RIGHT (vertical
    -- component preserved so the row stays aligned with the chosen
    -- corner). CENTER stays CENTER.
    local function mirrorAnchor(a)
        if a == "CENTER" then return "CENTER" end
        if a == "TOP" then return "BOTTOM" end
        if a == "BOTTOM" then return "TOP" end
        if a:find("LEFT") then return (a:gsub("LEFT", "RIGHT")) end
        if a:find("RIGHT") then return (a:gsub("RIGHT", "LEFT")) end
        return a
    end
    local relPoint = mirrorAnchor(anchor)

    -- Compact mode: glue the first icon to the right of the class icon
    -- (or to the left of the frame if no icon), forcing growX = RIGHT.
    local compact = db.compactMode and true or false
    if compact then growX = "RIGHT" end

    for i = 1, maxCount do
        local b = frame._auras[i]
        b:SetSize(size, size)
        b:ClearAllPoints()
        if i == 1 then
            if compact and db.showClassIcon and frame.classIcon and frame.classIcon:IsShown() then
                b:SetPoint("LEFT", frame.classIcon, "RIGHT", 4, 0)
            elseif compact then
                b:SetPoint("LEFT", frame, "LEFT", 2, 0)
            else
                b:SetPoint(relPoint, frame, anchor, db.aurasX or 0, db.aurasY or 0)
            end
        else
            local prev = frame._auras[i - 1]
            if growX == "LEFT" then
                b:SetPoint("RIGHT", prev, "LEFT", -spacing, 0)
            else
                b:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
            end
        end
        TW.ApplyAuraTextLayout(b, db)
    end
end

-- ============================================================
-- AURA FILTER + UPDATE
-- ============================================================
-- Returns the spellId only if it's a non-secret regular value. Secret
-- spellIds are unusable (can't index user tables), treat as nil.
-- Order matters: isSecret check BEFORE the nil comparison, since
-- `secret == nil` itself taints in 12.0.
local function getSpellID(aura)
    local sid
    pcall(function() sid = aura.spellId end)
    if isSecret(sid) then return nil end
    if sid == nil then return nil end
    return sid
end

-- DandersFrames / Cell pattern: post-scan boss debuff classification.
-- We iterate ALL harmful auras (broad scan) and then check each one
-- against the 5 RAID-relevant filter strings via the C function
-- IsAuraFilteredOutByInstanceID. If ANY filter accepts the aura, it's
-- a boss debuff. This is secret-safe — the C function doesn't read
-- the secret-tagged isBossAura field, only the auraInstanceID (regular).
local _IsAuraFilteredOut = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
-- Conservative set: only Blizzard's actually-boss-related classifiers.
-- HARMFUL|DISPELLABLE and HARMFUL|RAID_PLAYER_DISPELLABLE are NOT in
-- the list — they match every dispellable debuff (player cooldowns
-- like the DK "Recently Raised" 10-min Raise Ally lockout get tagged
-- dispellable C-side and would leak in).
local BOSS_FILTERS = {
    "HARMFUL|RAID",            -- Blizzard's primary "show on raid frame" filter
    "HARMFUL|RAID_IN_COMBAT",  -- combat-only raid debuffs
    "HARMFUL|IMPORTANT",       -- M+ / dungeon importance flag
}

local function passesFilter(unit, aura, db)
    if not aura then return false end
    local sid = getSpellID(aura)

    -- Blacklist beats everything; whitelist beats mode.
    if sid then
        if db.auraBlacklist and db.auraBlacklist[sid] then return false end
        if db.auraWhitelist and db.auraWhitelist[sid] then return true  end
    end

    local mode = db.auraFilterMode or "ALL"
    if mode == "WHITELIST" then return false end

    -- ALL and BOSS modes: trust the iteration. No Blizzard filter string
    -- cleanly maps to "boss debuff only" — HARMFUL|RAID misses many real
    -- boss mechanics (observed on Chimaerus while DandersFrames showed
    -- them), and HARMFUL|DISPELLABLE leaks player cooldowns. The robust
    -- approach (DandersFrames pattern: directDebuffShowAll = true by
    -- default) is to show every HARMFUL aura and let the blacklist
    -- handle noise. The default blacklist already covers Sated /
    -- Exhaustion / Temporal Displacement / DK rez lockout / etc.
    return true
end

local function getStacks(aura)
    local n
    pcall(function() n = aura.applications end)
    return n  -- may be nil or secret; caller must guard
end

function TW.UpdateAuras(frame)
    if not frame or not frame._unit then return end
    local db = TW:GetDB()
    if not db.showAuras then
        if TW._renderDebug then
            print(string.format("|cff00ff96TW render:|r %s SKIP (showAuras=false)",
                tostring(frame._unit)))
        end
        return
    end
    local maxCount = db.aurasMaxCount or 5
    ensurePool(frame, maxCount)

    -- Clear any leftover test-loop OnUpdate handlers when switching from
    -- test mode to a real unit
    if frame._auras then
        for _, b in ipairs(frame._auras) do
            if b._testAcc ~= nil then b:SetScript("OnUpdate", nil); b._testAcc = nil end
        end
    end

    local found, foundIdx = {}, {}
    local mode = db.auraFilterMode or "ALL"
    iterHarmful(frame._unit, maxCount * 4, function(aura, srcIdx)
        if passesFilter(frame._unit, aura, db) then
            -- "Only stacks > 1" filter: only applied when stacks is a
            -- non-secret regular number; otherwise we can't compare and
            -- we let the aura through.
            if db.aurasOnlyStacks then
                local stacks = getStacks(aura)
                if isSecret(stacks) or stacks == nil or stacks <= 1 then
                    return
                end
            end
            found[#found + 1] = aura
            foundIdx[#foundIdx + 1] = srcIdx
            if #found >= maxCount then return true end
        end
    end, mode)

    if TW._renderDebug then
        print(string.format("|cff00ff96TW render:|r %s mode=%s found=%d showAuras=%s onlyStacks=%s",
            tostring(frame._unit), tostring(mode), #found,
            tostring(db.showAuras), tostring(db.aurasOnlyStacks)))
        for i, a in ipairs(found) do
            local sid, sname, stacks = "?", "?", "?"
            pcall(function() sid    = tostring(a.spellId      or "?") end)
            pcall(function() sname  = tostring(a.name         or "?") end)
            pcall(function() stacks = tostring(a.applications or "?") end)
            print(string.format("    found[%d] %s id=%s stacks=%s", i, sname, sid, stacks))
        end
    end

    frame._visibleAuraCount = 0  -- reset; render loop updates as it shows
    for i = 1, maxCount do
        local b = frame._auras[i]
        local aura = found[i]
        if aura then
            -- Tooltip plumbing: remember the unit + harmful index (legacy
            -- API) and the auraInstanceID (modern secret-safe API). The
            -- OnEnter handler prefers SetUnitBuffByAuraInstanceID when the
            -- index is -1 (ForEachAura path doesn't expose it). Stash the
            -- spellID too — OnEnter appends it to the tooltip so tanks
            -- can read it directly and blacklist via the Filters tab.
            local _instId, _spellId
            pcall(function() _instId = aura.auraInstanceID end)
            pcall(function() _spellId = aura.spellId end)
            b._unit, b._harmfulIndex, b._auraInstanceID, b._spellId, b._testMode =
                frame._unit, foundIdx[i], _instId, _spellId, false
            -- Icon: SetTexture accepts secret values safely (Cell pattern).
            -- Pass directly via pcall — never evaluate truthiness of a
            -- possibly-secret value (`if icon then` would taint).
            local icon
            pcall(function() icon = aura.icon end)
            if isSecret(icon) then
                pcall(b.icon.SetTexture, b.icon, icon)
            elseif icon ~= nil then
                b.icon:SetTexture(icon)
            end

            -- auraInstanceID is a non-secret regular value, used to call
            -- the Blizzard secret-aware aura APIs.
            local instId
            pcall(function() instId = aura.auraInstanceID end)

            -- Stacks — DandersFrames pattern: always use the C API
            -- GetAuraApplicationDisplayCount(unit, instId, min, max). It
            -- returns the count as a string (secret-tagged if the aura
            -- is secret-sourced) and handles every edge case C-side:
            --   below `min` → empty string (hide)
            --   above `max` → "*" (overflow indicator)
            --   otherwise  → the count
            -- SetText accepts secret strings safely. Reading
            -- aura.applications directly was unreliable: it returns nil
            -- or 0 on many secret-tagged auras even when there ARE
            -- stacks, hiding legitimate stack counts.
            b.stacks:SetText("")
            if instId ~= nil
               and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
                local stackText
                pcall(function()
                    stackText = C_UnitAuras.GetAuraApplicationDisplayCount(
                        frame._unit, instId, 2, 99)
                end)
                if stackText ~= nil then
                    pcall(b.stacks.SetText, b.stacks, stackText)
                end
            else
                -- Pre-12.0 / Classic fallback: read applications directly.
                local stacks = getStacks(aura)
                if type(stacks) == "number" and stacks > 1 then
                    b.stacks:SetText(tostring(stacks))
                end
            end

            -- Cooldown swipe + timer text:
            --  • Non-secret values → use our custom b.timer FontString
            --  • Otherwise → Blizzard Duration object + built-in countdown
            local dur, exp
            pcall(function() dur = aura.duration end)
            pcall(function() exp = aura.expirationTime end)

            -- Cooldown swipe — DandersFrames pattern: PREFER the secret-
            -- safe SetCooldownFromDurationObject API. The Duration object
            -- returned by GetAuraDuration handles secret-tagged duration
            -- / expirationTime fields C-side, so the swipe renders even
            -- on hostile-sourced auras where dur/exp are sealed. Fall
            -- back to direct SetCooldown(start, dur) only when neither
            -- the modern API nor a Duration object is available.
            local cooldownSet = false
            if instId ~= nil
               and C_UnitAuras and C_UnitAuras.GetAuraDuration
               and b.cd.SetCooldownFromDurationObject then
                local durObj
                local ok = pcall(function()
                    durObj = C_UnitAuras.GetAuraDuration(frame._unit, instId)
                end)
                if ok and durObj ~= nil and not isSecret(durObj) then
                    b.cd:SetHideCountdownNumbers(true)
                    pcall(b.cd.SetCooldownFromDurationObject, b.cd, durObj)
                    cooldownSet = true
                end
            end
            if cooldownSet then
                -- Best-effort: read the regular dur/exp into _exp for the
                -- live timer text. If they're secret we just leave timer
                -- blank — the swipe is the primary visual.
                if not isSecret(exp) and type(exp) == "number" and exp > 0 then
                    b._exp = exp
                    b.timer:SetText(formatTime(exp - GetTime()))
                else
                    b._exp = nil
                    b.timer:SetText("")
                end
            elseif not isSecret(dur) and not isSecret(exp)
                   and dur and exp and dur > 0 and exp > 0 then
                -- Pre-12.0 / Classic fallback: regular SetCooldown.
                b.cd:SetHideCountdownNumbers(true)
                b.cd:SetCooldown(exp - dur, dur)
                b._exp = exp
                b.timer:SetText(formatTime(exp - GetTime()))
            else
                b.cd:Clear()
                b.timer:SetText("")
                b._exp = nil
            end
            b:Show()
            frame._visibleAuraCount = i  -- track last visible index
            if TW._renderDebug then
                local w, h = b:GetSize()
                local point, relTo, relPoint, ox, oy = b:GetPoint(1)
                local hasIcon = b.icon:GetTexture() ~= nil
                print(string.format("    button[%d] shown=%s size=%dx%d point=%s offset=%d,%d icon=%s",
                    i, tostring(b:IsShown()), w, h,
                    tostring(point), ox or 0, oy or 0, tostring(hasIcon)))
            end
        else
            b._exp = nil
            b:Hide()
        end
    end

    -- Re-anchor private aura hosts so they sit immediately to the right
    -- of the last visible regular debuff icon (inline-row mode). When
    -- the visible debuff count changes (debuff applied / expired) the
    -- private aura row shifts to keep the layout continuous.
    if TW.ApplyPrivateAuras then TW:ApplyPrivateAuras(frame) end
end

-- ============================================================
-- TEST AURAS
-- ============================================================
local TEST_AURA_DATA = {
    -- {iconId, baseStacks, duration}
    { 135777, 1, 12 }, -- Spell_Holy_Renew
    { 136118, 3, 25 }, -- Spell_Shadow_Curseofmannoroth
    { 132298, 5, 8 },  -- Ability_Warrior_DefensiveStance
    { 136210, 2, 18 }, -- Spell_Shadow_DemonicEmpathy
    { 136054, 7, 30 }, -- Spell_Shadow_DeathScream
}

function TW:PrintAuraDebug()
    local L = TW.L
    print("|cff00ff96TankWatch:|r " .. (L["aura diagnostic:"] or "aura diagnostic:"))

    local function tryFE(unit)
        if not (AuraUtil and AuraUtil.ForEachAura) then return "n/a", 0 end
        local count = 0
        local ok = pcall(function()
            AuraUtil.ForEachAura(unit, "HARMFUL", 40, function(aura)
                count = count + 1
                local sid, sname, stacks = "?", "?", "?"
                pcall(function() sid    = tostring(aura.spellId      or "?") end)
                pcall(function() sname  = tostring(aura.name         or "?") end)
                pcall(function() stacks = tostring(aura.applications or "?") end)
                print(string.format("      FE[%d] %s id=%s stacks=%s",
                    count, sname, sid, stacks))
            end)
        end)
        return ok and "ok" or "threw", count
    end

    local function tryIdx(unit)
        if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return "n/a", 0 end
        local count = 0
        for i = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
            if not ok then return "threw", count end
            if not aura then break end
            count = count + 1
            local sid, sname, stacks = "?", "?", "?"
            pcall(function() sid    = tostring(aura.spellId      or "?") end)
            pcall(function() sname  = tostring(aura.name         or "?") end)
            pcall(function() stacks = tostring(aura.applications or "?") end)
            print(string.format("      IDX[%d] %s id=%s stacks=%s",
                count, sname, sid, stacks))
        end
        return "ok", count
    end

    -- Per-aura filter classification: dumps every HARMFUL aura on the
    -- unit with its spellID, name, stacks, and which BOSS_FILTERS accept
    -- it. Use this to identify a junk debuff leaking through the BOSS
    -- filter so it can be added to the blacklist.
    local function dumpFilters(unit)
        if not (C_UnitAuras and C_UnitAuras.GetAuraSlots
                and C_UnitAuras.GetAuraDataBySlot) then return end
        local returns = { pcall(C_UnitAuras.GetAuraSlots, unit, "HARMFUL", 40) }
        if not returns[1] then return end
        for i = 3, #returns do
            local slot = returns[i]
            local ok, aura = pcall(C_UnitAuras.GetAuraDataBySlot, unit, slot)
            if ok and aura then
                local sid, sname, stacks = "?", "?", "?"
                pcall(function() sid    = tostring(aura.spellId      or "?") end)
                pcall(function() sname  = tostring(aura.name         or "?") end)
                pcall(function() stacks = tostring(aura.applications or "?") end)
                local instId
                pcall(function() instId = aura.auraInstanceID end)
                local matches = {}
                if type(instId) == "number" and _IsAuraFilteredOut then
                    for _, f in ipairs(BOSS_FILTERS) do
                        local notOut
                        pcall(function() notOut = not _IsAuraFilteredOut(unit, instId, f) end)
                        if notOut then
                            matches[#matches + 1] = f:gsub("HARMFUL|", "")
                        end
                    end
                end
                local tag = (#matches > 0) and ("|cff00ff00BOSS|r " .. table.concat(matches, ","))
                    or "|cffaaaaaa(none)|r"
                print(string.format("      %s id=%s stacks=%s  %s",
                    sname, sid, stacks, tag))
            end
        end
    end

    local function scan(unit, label)
        local exists = false
        pcall(function() exists = UnitExists(unit) end)
        if not exists then return end
        local nm = "?"
        pcall(function() nm = UnitName(unit) or "?" end)
        print(string.format("  %s (%s) [%s]:", unit, tostring(nm), label or "?"))
        local s1, c1 = tryFE(unit)
        print(string.format("    AuraUtil.ForEachAura → %s, %d auras", s1, c1))
        local s2, c2 = tryIdx(unit)
        print(string.format("    C_UnitAuras.GetAuraDataByIndex → %s, %d auras", s2, c2))
        print("    per-aura filter match:")
        dumpFilters(unit)
    end

    local TANK = TW.TankFrames or {}
    local seen = false
    for i = 1, (TW.MAX_TANKS or 8) do
        local f = TANK[i]
        if f and f._unit then
            seen = true
            scan(f._unit, "tank frame " .. i)
        end
    end
    if not seen then print("  (no tank frames active)") end
    scan("player", "player (sanity check)")
end

-- Looping test aura: each button gets its own OnUpdate that ticks the timer,
-- and on expiry resets duration + picks a new random stack count. Gives the
-- user a live preview with stacks changing and durations cycling.
local function startTestLoop(b, data)
    local maxStacks = data[2]
    b._testDuration = data[3]
    b._testStart    = GetTime() - (data[3] * 0.4)
    b._testStacks   = math.random(1, maxStacks + 2)
    b.cd:SetCooldown(b._testStart, b._testDuration)
    b.stacks:SetText(b._testStacks > 1 and tostring(b._testStacks) or "")

    b:SetScript("OnUpdate", function(self, elapsed)
        self._testAcc = (self._testAcc or 0) + elapsed
        if self._testAcc < 0.1 then return end  -- update at 10 Hz
        self._testAcc = 0

        local now = GetTime()
        local remaining = (self._testStart + self._testDuration) - now
        if remaining <= 0 then
            -- Cycle: new duration, fresh start, fresh stacks
            self._testDuration = math.random(8, 30)
            self._testStart    = now
            self._testStacks   = math.random(1, maxStacks + 3)
            self.cd:SetCooldown(self._testStart, self._testDuration)
            self.stacks:SetText(self._testStacks > 1 and tostring(self._testStacks) or "")
            remaining = self._testDuration
        elseif math.random() < 0.04 then
            -- Occasional stack change mid-fight (≈4% per tick, ~0.4 chance/s)
            self._testStacks = math.max(1, math.min(maxStacks + 4, self._testStacks + (math.random(0, 1) == 0 and -1 or 1)))
            self.stacks:SetText(self._testStacks > 1 and tostring(self._testStacks) or "")
        end
        self.timer:SetText(format("%d", math.ceil(remaining)))
    end)
end

local function stopTestLoop(b)
    b:SetScript("OnUpdate", nil)
    b._testAcc = 0
end

function TW.SetTestAuras(frame, tankIndex)
    local db = TW:GetDB()
    if not db.showAuras then
        if frame._auras then
            for _, a in ipairs(frame._auras) do stopTestLoop(a); a:Hide() end
        end
        return
    end
    TW.LayoutAuras(frame, db)
    local maxCount = math.min(db.aurasMaxCount or 5, #TEST_AURA_DATA)
    ensurePool(frame, db.aurasMaxCount or 5)
    frame._visibleAuraCount = 0
    for i = 1, db.aurasMaxCount or 5 do
        local b = frame._auras[i]
        local data = TEST_AURA_DATA[i]
        if data and i <= (1 + (tankIndex % maxCount)) then
            b.icon:SetTexture(data[1])
            startTestLoop(b, data)
            b._testMode = true
            b._testName = data[5] or data[6] or ("Debuff " .. i)
            b._unit, b._harmfulIndex = nil, nil
            b:Show()
            frame._visibleAuraCount = i
        else
            stopTestLoop(b)
            b:Hide()
        end
    end
    -- Trigger private aura test rendering inline with the test debuffs.
    if TW.ApplyPrivateAuras then TW:ApplyPrivateAuras(frame) end
end

-- ============================================================
-- GLOBAL TIMER TICKER
-- One OnUpdate (instead of one per aura icon) refreshes every visible
-- timer's countdown text at 10 Hz. Buttons opt in by setting `b._exp`
-- on bind; cleared on hide / rebind. Test-mode buttons keep their own
-- OnUpdate (they do more than just count down — they cycle durations
-- and animate stacks).
-- ============================================================
do
    local tickerFrame = CreateFrame("Frame", nil, UIParent)
    local acc = 0
    tickerFrame:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.1 then return end
        acc = 0
        local now = GetTime()
        if not TW.TankFrames then return end
        for i = 1, (TW.MAX_TANKS or 8) do
            local f = TW.TankFrames[i]
            if f and f:IsShown() and f._auras then
                for _, b in ipairs(f._auras) do
                    if b._exp and b:IsShown() then
                        local r = b._exp - now
                        if r <= 0 then b.timer:SetText("")
                        else            b.timer:SetText(formatTime(r)) end
                    end
                end
            end
        end
    end)
end
