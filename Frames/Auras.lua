local addonName, TW = ...

local CreateFrame = CreateFrame
local GetTime = GetTime
local format = string.format
local AuraUtil = AuraUtil
local C_UnitAuras = C_UnitAuras
local MAX_TANKS = TW.MAX_TANKS

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

    -- Stack count: BIG, prominent (this is the whole point of the addon)
    local stacks = cd:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    stacks:SetPoint("CENTER", b, "CENTER", 0, 0)
    stacks:SetTextColor(1, 0.9, 0.1)
    stacks:SetDrawLayer("OVERLAY", 7)
    b.stacks = stacks

    -- Timer below
    local timer = cd:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    timer:SetPoint("TOP", b, "BOTTOM", 0, -1)
    timer:SetTextColor(1, 0.85, 0.1)
    timer:SetDrawLayer("OVERLAY", 7)
    b.timer = timer

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
    end
end

-- ============================================================
-- AURA FILTER + UPDATE
-- ============================================================
local function getSpellID(aura)
    local ok, sid = pcall(function() return aura.spellId end)
    if ok and sid then return sid end
    return nil
end

local function passesFilter(aura, db)
    if not aura then return false end
    local sid = getSpellID(aura)
    if sid then
        if db.auraBlacklist and db.auraBlacklist[sid] then return false end
        if db.auraWhitelist and db.auraWhitelist[sid] then return true  end
    end
    -- default: only boss-cast (isBossAura is sometimes a secret value, hence pcall)
    local ok, isBoss = pcall(function() return aura.isBossAura end)
    return ok and isBoss == true
end

local function getStacks(aura)
    local ok, n = pcall(function() return aura.applications end)
    if ok and n then return n end
    return 0
end

function TW.UpdateAuras(frame)
    if not frame or not frame._unit then return end
    local db = TW:GetDB()
    if not db.showAuras then return end
    local maxCount = db.aurasMaxCount or 5
    ensurePool(frame, maxCount)

    local found = {}
    pcall(function()
        AuraUtil.ForEachAura(frame._unit, "HARMFUL", maxCount * 4, function(aura)
            if passesFilter(aura, db) then
                local stacks = getStacks(aura)
                if not db.aurasOnlyStacks or stacks > 1 then
                    found[#found + 1] = aura
                    if #found >= maxCount then return true end
                end
            end
        end)
    end)

    for i = 1, maxCount do
        local b = frame._auras[i]
        local aura = found[i]
        if aura then
            local ok, icon = pcall(function() return aura.icon end)
            if ok and icon then b.icon:SetTexture(icon) end

            local stacks = getStacks(aura)
            b.stacks:SetText(stacks > 1 and tostring(stacks) or "")

            local ok2, dur = pcall(function() return aura.duration end)
            local ok3, exp = pcall(function() return aura.expirationTime end)
            if ok2 and ok3 and dur and dur > 0 and exp and exp > 0 then
                b.cd:SetCooldown(exp - dur, dur)
                b.timer:SetText(formatTime(exp - GetTime()))
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

function TW.SetTestAuras(frame, tankIndex)
    local db = TW:GetDB()
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
