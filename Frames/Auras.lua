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

-- Robust HARMFUL aura iteration. Tries AuraUtil.ForEachAura first; falls
-- back to C_UnitAuras.GetAuraDataByIndex if it throws.
local function iterHarmful(unit, max, callback)
    if AuraUtil and AuraUtil.ForEachAura then
        local ok = pcall(function()
            AuraUtil.ForEachAura(unit, "HARMFUL", max, callback)
        end)
        if ok then return "ForEachAura" end
    end
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, max do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
            if not ok or not aura then break end
            local stop = callback(aura)
            if stop then break end
        end
        return "GetAuraDataByIndex"
    end
    return nil
end

-- ============================================================
-- AURA BUTTON
-- ============================================================
local function CreateAuraButton(parent, index)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(28, 28); b:Hide()

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
    for i = 1, count do
        if not frame._auras[i] then
            frame._auras[i] = CreateAuraButton(frame, i)
        end
    end
    for i = count + 1, #frame._auras do frame._auras[i]:Hide() end
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

    for i = 1, maxCount do
        local b = frame._auras[i]
        b:SetSize(size, size)
        b:ClearAllPoints()
        if i == 1 then
            b:SetPoint(relPoint, frame, anchor, db.aurasX or 0, db.aurasY or 0)
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
-- Order matters: isSecret check BEFORE any comparison, since `secret == nil`
-- itself can taint.
local function getSpellID(aura)
    local sid
    pcall(function() sid = aura.spellId end)
    if sid == nil then return nil end
    if isSecret(sid) then return nil end
    return sid
end

local function passesFilter(aura, db)
    if not aura then return false end
    local sid = getSpellID(aura)

    -- Blacklist / whitelist only apply when spellId is a regular value
    if sid then
        if db.auraBlacklist and db.auraBlacklist[sid] then return false end
        if db.auraWhitelist and db.auraWhitelist[sid] then return true  end
    end

    local mode = db.auraFilterMode or "ALL"
    if mode == "ALL"       then return true  end
    if mode == "WHITELIST" then return false end
    -- BOSS mode: in 12.0 `isBossAura` is secret-tagged. We use
    -- `isFromPlayerOrPlayerPet` (regular value, non-secret) as a proxy:
    -- HARMFUL auras NOT applied by the player/pet are almost certainly
    -- from a hostile NPC (boss, mob, environment).
    local fromMe
    pcall(function() fromMe = aura.isFromPlayerOrPlayerPet end)
    if fromMe == nil or isSecret(fromMe) then
        -- Fallback: if isBossAura is somehow available and non-secret, use it
        local isBoss
        pcall(function() isBoss = aura.isBossAura end)
        if isBoss == nil or isSecret(isBoss) then return false end
        return isBoss == true
    end
    return fromMe == false
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

    local found = {}
    iterHarmful(frame._unit, maxCount * 4, function(aura)
        if passesFilter(aura, db) then
            -- "Only stacks > 1" filter: only applied when stacks is a
            -- non-secret regular number; otherwise we can't compare and
            -- we let the aura through.
            if db.aurasOnlyStacks then
                local stacks = getStacks(aura)
                if stacks == nil or isSecret(stacks) or stacks <= 1 then
                    return
                end
            end
            found[#found + 1] = aura
            if #found >= maxCount then return true end
        end
    end)

    for i = 1, maxCount do
        local b = frame._auras[i]
        local aura = found[i]
        if aura then
            -- Icon: SetTexture accepts secret values safely (Cell pattern)
            local icon
            pcall(function() icon = aura.icon end)
            if icon then b.icon:SetTexture(icon) end

            -- auraInstanceID is a non-secret regular value, used to call
            -- the Blizzard secret-aware aura APIs.
            local instId
            pcall(function() instId = aura.auraInstanceID end)

            -- Stacks: prefer Blizzard's secret-aware display API
            -- (DandersFrames pattern). Returns "" below min, the count, or
            -- "*" above max — already a display-ready string.
            local stackTxt
            if instId and not isSecret(instId)
               and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
                pcall(function()
                    stackTxt = C_UnitAuras.GetAuraApplicationDisplayCount(
                        frame._unit, instId, 2, 99)
                end)
            end
            if stackTxt then
                b.stacks:SetText(stackTxt)
            else
                local stacks = getStacks(aura)
                if stacks == nil then
                    b.stacks:SetText("")
                elseif isSecret(stacks) then
                    b.stacks:SetText("?")
                elseif stacks > 1 then
                    b.stacks:SetText(tostring(stacks))
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

            if dur and exp and not isSecret(dur) and not isSecret(exp)
               and dur > 0 and exp > 0 then
                b.cd:SetHideCountdownNumbers(true)
                b.cd:SetCooldown(exp - dur, dur)
                b.timer:SetText(formatTime(exp - GetTime()))
            elseif instId and not isSecret(instId)
                   and C_UnitAuras and C_UnitAuras.GetAuraDuration
                   and b.cd.SetCooldownFromDurationObject then
                local durObj
                local ok = pcall(function()
                    durObj = C_UnitAuras.GetAuraDuration(frame._unit, instId)
                end)
                if ok and durObj then
                    b.cd:SetHideCountdownNumbers(false) -- Blizzard's countdown handles secrets
                    b.cd:SetCooldownFromDurationObject(durObj)
                    b.timer:SetText("") -- our font hides; native countdown takes over
                else
                    b.cd:Clear()
                    b.timer:SetText("")
                end
            else
                b.cd:Clear()
                b.timer:SetText("")
            end
            b:Show()
        else
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

function TW.SetTestAuras(frame, tankIndex)
    local db = TW:GetDB()
    if not db.showAuras then
        if frame._auras then
            for _, a in ipairs(frame._auras) do a:Hide() end
        end
        return
    end
    -- Apply current text positioning + visibility toggles to existing buttons
    TW.LayoutAuras(frame, db)
    local maxCount = math.min(db.aurasMaxCount or 5, #TEST_AURA_DATA)
    ensurePool(frame, db.aurasMaxCount or 5)
    for i = 1, db.aurasMaxCount or 5 do
        local b = frame._auras[i]
        local data = TEST_AURA_DATA[i]
        if data and i <= (1 + (tankIndex % maxCount)) then
            b.icon:SetTexture(data[1])
            b.stacks:SetText(data[2] > 1 and tostring(data[2]) or "")
            b.cd:SetCooldown(GetTime() - (data[3] * 0.4), data[3])
            b.timer:SetText(format("%d", data[3] - data[3] * 0.4))
            b:Show()
        else
            b:Hide()
        end
    end
end
