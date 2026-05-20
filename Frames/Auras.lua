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
-- BOSS mode: only the specialized "RAID-relevant" filter strings. Each
-- aura returned by ForEachAura under one of these filters is already
-- classified by Blizzard as a boss debuff / raid-important aura — no
-- post-filtering needed. Excludes plain "HARMFUL" so self-cast debuffs
-- like Sated / Temporal Displacement / Exhaustion don't leak in.
-- ALL mode: plain HARMFUL.
local SCAN_FILTERS_BOSS = {
    "HARMFUL|RAID",
    "HARMFUL|RAID_IN_COMBAT",
    "HARMFUL|IMPORTANT",
    "HARMFUL|DISPELLABLE",
    "HARMFUL|RAID_PLAYER_DISPELLABLE",
}
local SCAN_FILTERS_ALL = { "HARMFUL" }
local function iterHarmful(unit, max, callback, mode)
    local SCAN_FILTERS = (mode == "ALL") and SCAN_FILTERS_ALL or SCAN_FILTERS_BOSS
    if _G.AuraUtil and AuraUtil.ForEachAura then
        local seen, emitted, stopAll = {}, 0, false
        for _, filter in ipairs(SCAN_FILTERS) do
            if stopAll then break end
            -- usePackedAura = true so the callback receives the aura
            -- TABLE (with .spellId, .applications, etc.) instead of
            -- unpacked positional args.
            pcall(AuraUtil.ForEachAura, unit, filter, max, function(aura)
                if not aura then return true end
                local instId
                pcall(function() instId = aura.auraInstanceID end)
                local key = (type(instId) == "number") and instId
                if key and seen[key] then return false end
                if key then seen[key] = true end
                -- No usable index for SetUnitDebuff tooltip API when
                -- coming from ForEachAura, but the tooltip path now
                -- prefers SetUnitBuffByAuraInstanceID anyway (modern
                -- secret-safe API) so we pass -1 as a sentinel.
                if callback(aura, -1) then
                    stopAll = true
                    return true
                end
                emitted = emitted + 1
                if emitted >= max then
                    stopAll = true
                    return true
                end
                return false
            end, true)
        end
        return "ForEachAura+filters"
    elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        -- Fallback path (older builds): plain HARMFUL indexed scan.
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
        if type(instId) == "number"
           and GameTooltip.SetUnitBuffByAuraInstanceID then
            pcall(GameTooltip.SetUnitBuffByAuraInstanceID, GameTooltip,
                  unit, instId, "HARMFUL")
        elseif idx and idx > 0 and GameTooltip.SetUnitDebuff then
            pcall(GameTooltip.SetUnitDebuff, GameTooltip, unit, idx)
        end
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
    if created and TW.ApplyFonts then TW:ApplyFonts() end
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
    local relPoint = (anchor == "LEFT") and "RIGHT" or
                     (anchor == "RIGHT") and "LEFT" or anchor

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

-- DandersFrames-style boss debuff detection. Cascades through every
-- HARMFUL|* filter Blizzard ships, returns true on the first one the
-- aura passes. Single "HARMFUL|RAID" is too strict — M+/dungeon
-- debuffs are often only tagged IMPORTANT or RAID_IN_COMBAT. All checks
-- are secret-safe (the API doesn't read the secret-tagged isBossAura).
-- Returns nil if the API isn't available (Classic / older retail).
local _IsAuraFilteredOut = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
local BOSS_FILTERS = {
    "HARMFUL|RAID",
    "HARMFUL|RAID_IN_COMBAT",
    "HARMFUL|IMPORTANT",
    "HARMFUL|DISPELLABLE",
    "HARMFUL|RAID_PLAYER_DISPELLABLE",
}
local function passesRaidFilter(unit, aura)
    if not _IsAuraFilteredOut or not aura then return nil end
    local instId
    pcall(function() instId = aura.auraInstanceID end)
    if isSecret(instId) or type(instId) ~= "number" then return nil end
    for _, f in ipairs(BOSS_FILTERS) do
        local notFiltered
        pcall(function() notFiltered = not _IsAuraFilteredOut(unit, instId, f) end)
        if notFiltered == true then return true end
    end
    -- None of the Blizzard boss-debuff filters claimed this aura.
    -- Return nil (not false) so the caller can still try the legacy
    -- isFromPlayerOrPlayerPet / sourceUnit cascade, which catches
    -- hostile-cast auras Blizzard doesn't tag specifically.
    return nil
end

local function passesFilter(unit, aura, db)
    if not aura then return false end
    local sid = getSpellID(aura)

    -- Blacklist always wins; whitelist forces show even when iteration
    -- mode would filter the aura out.
    if sid then
        if db.auraBlacklist and db.auraBlacklist[sid] then return false end
        if db.auraWhitelist and db.auraWhitelist[sid] then return true  end
    end

    local mode = db.auraFilterMode or "ALL"
    if mode == "WHITELIST" then return false end
    -- ALL and BOSS modes both pass through here: the iteration step
    -- already restricted the aura set (BOSS = specialized RAID filters,
    -- ALL = plain HARMFUL), so we just trust what came out. Source-based
    -- heuristics (isFromPlayerOrPlayerPet / isBossAura / sourceUnit) are
    -- unreliable in 12.0 due to secret-value tagging on hostile sources,
    -- and the permissive fallback was leaking non-boss debuffs (Sated /
    -- Temporal Displacement / Exhaustion).
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
    if not db.showAuras then return end
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

    for i = 1, maxCount do
        local b = frame._auras[i]
        local aura = found[i]
        if aura then
            -- Tooltip plumbing: remember the unit + harmful index (legacy
            -- API) and the auraInstanceID (modern secret-safe API). The
            -- OnEnter handler prefers SetUnitBuffByAuraInstanceID when the
            -- index is -1 (ForEachAura path doesn't expose it).
            local _instId
            pcall(function() _instId = aura.auraInstanceID end)
            b._unit, b._harmfulIndex, b._auraInstanceID, b._testMode =
                frame._unit, foundIdx[i], _instId, false
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

            -- Stacks: prefer the regular aura.applications field (non-secret
            -- on friendly raid units, which is where TankWatch operates).
            -- Fall back to Blizzard's secret-aware display API only if the
            -- direct read returns secret or nil — handles edge cases where
            -- the aura record is sealed by a hostile source.
            local stacks = getStacks(aura)
            if not isSecret(stacks) and type(stacks) == "number" then
                if stacks > 1 then
                    b.stacks:SetText(tostring(stacks))
                else
                    b.stacks:SetText("")
                end
            else
                local stackTxt
                if not isSecret(instId) and instId
                   and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
                    pcall(function()
                        stackTxt = C_UnitAuras.GetAuraApplicationDisplayCount(
                            frame._unit, instId, 2, 99)
                    end)
                end
                if isSecret(stackTxt) then
                    pcall(b.stacks.SetText, b.stacks, stackTxt)
                elseif stackTxt ~= nil and stackTxt ~= "" then
                    b.stacks:SetText(stackTxt)
                else
                    b.stacks:SetText("")
                end
            end

            -- Cooldown swipe + timer text:
            --  • Non-secret values → use our custom b.timer FontString
            --  • Otherwise → Blizzard Duration object + built-in countdown
            local dur, exp
            pcall(function() dur = aura.duration end)
            pcall(function() exp = aura.expirationTime end)

            if not isSecret(dur) and not isSecret(exp)
               and dur and exp and dur > 0 and exp > 0 then
                b.cd:SetHideCountdownNumbers(true)
                b.cd:SetCooldown(exp - dur, dur)
                -- Live countdown: just tag the button with _exp; a single
                -- global ticker (registered once at file load) walks every
                -- visible button at 10 Hz and refreshes the text. Replaces
                -- the previous per-button OnUpdate (40+ tickers for a full
                -- raid of 8 tanks × 5 auras).
                b._exp = exp
                b.timer:SetText(formatTime(exp - GetTime()))
            elseif not isSecret(instId) and instId
                   and C_UnitAuras and C_UnitAuras.GetAuraDuration
                   and b.cd.SetCooldownFromDurationObject then
                local durObj
                local ok = pcall(function()
                    durObj = C_UnitAuras.GetAuraDuration(frame._unit, instId)
                end)
                if ok and durObj ~= nil and not isSecret(durObj) then
                    b.cd:SetHideCountdownNumbers(false)
                    b.cd:SetCooldownFromDurationObject(durObj)
                    b.timer:SetText("")
                    b._exp = nil
                else
                    b.cd:Clear()
                    b.timer:SetText("")
                    b._exp = nil
                end
            else
                b.cd:Clear()
                b.timer:SetText("")
                b._exp = nil
            end
            b:Show()
        else
            b._exp = nil
            b:Hide()
        end
    end
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
        else
            stopTestLoop(b)
            b:Hide()
        end
    end
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
