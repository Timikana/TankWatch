local addonName, TW = ...

local CreateFrame = CreateFrame
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitName, UnitClass, UnitExists = UnitName, UnitClass, UnitExists
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local IsInRaid, IsInGroup = IsInRaid, IsInGroup
local GetNumGroupMembers = GetNumGroupMembers
local format = string.format

local MAX_TANKS = TW.MAX_TANKS

local _pendingLayout = false

-- ============================================================
-- TANK DETECTION
-- ============================================================
local function collectTankUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid" .. i
            if UnitExists(u) and UnitGroupRolesAssigned(u) == "TANK" then
                units[#units + 1] = u
            end
        end
    elseif IsInGroup() then
        if UnitGroupRolesAssigned("player") == "TANK" then
            units[#units + 1] = "player"
        end
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) and UnitGroupRolesAssigned(u) == "TANK" then
                units[#units + 1] = u
            end
        end
    else
        -- Solo: show the player if their role is TANK or their spec is tank
        if UnitGroupRolesAssigned("player") == "TANK" then
            units[#units + 1] = "player"
        end
    end
    return units
end

-- ============================================================
-- COLOR HELPERS
-- ============================================================
local CLASS_COLORS = RAID_CLASS_COLORS or {}

local function classColor(unit)
    local _, cls = pcall(UnitClass, unit)
    if cls and CLASS_COLORS[cls] then
        local c = CLASS_COLORS[cls]
        return c.r, c.g, c.b
    end
    return 0.5, 0.5, 0.5
end

-- ============================================================
-- TEXT FORMATTERS
-- ============================================================
local function shortNum(n)
    if not n or n <= 0 then return "0" end
    if n >= 1e9 then return format("%.1fB", n / 1e9) end
    if n >= 1e6 then return format("%.1fM", n / 1e6) end
    if n >= 1e3 then return format("%.1fK", n / 1e3) end
    return tostring(math.floor(n))
end

local function formatHP(cur, max, fmt)
    if not cur or not max or max <= 0 then return "" end
    local pct = math.floor(cur / max * 100 + 0.5)
    if fmt == "PERCENT" then return pct .. "%"
    elseif fmt == "CURRENT" then return shortNum(cur)
    elseif fmt == "CURRENT_PERCENT" then return shortNum(cur) .. " (" .. pct .. "%)"
    else return shortNum(cur) .. " / " .. shortNum(max) end
end

-- ============================================================
-- FRAME CREATION
-- ============================================================
local function CreateTankFrame(index)
    local f = CreateFrame("Button", "TankWatchFrame" .. index, UIParent, "SecureUnitButtonTemplate,BackdropTemplate")
    f:SetSize(200, 36)
    f:SetAttribute("type1", "target")
    f:SetAttribute("type2", "focus")
    f:Hide()
    f._index = index

    -- Background
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f)
    f.bg:SetColorTexture(0, 0, 0, 0.6)

    -- Health bar
    local hp = CreateFrame("StatusBar", nil, f)
    hp:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    hp:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.healthBar = hp

    local hpBg = hp:CreateTexture(nil, "BACKGROUND")
    hpBg:SetAllPoints(hp)
    hpBg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
    hp.bg = hpBg

    -- Name + HP text
    local nameText = hp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetTextColor(1, 1, 1)
    f.nameText = nameText

    local hpText = hp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hpText:SetTextColor(0.95, 0.95, 0.95)
    f.healthText = hpText

    return f
end

function TW:EnsureCreated()
    if TW.TankContainer then return end
    local container = CreateFrame("Frame", "TankWatchContainer", UIParent)
    container:SetSize(200, 100)
    TW.TankContainer = container

    for i = 1, MAX_TANKS do
        TW.TankFrames[i] = CreateTankFrame(i)
        TW.TankFrames[i]:SetParent(container)
    end
end

-- ============================================================
-- LAYOUT
-- ============================================================
local VALID_ANCHOR9 = {
    TOPLEFT = 1, TOP = 1, TOPRIGHT = 1,
    LEFT = 1, CENTER = 1, RIGHT = 1,
    BOTTOMLEFT = 1, BOTTOM = 1, BOTTOMRIGHT = 1,
}

local function justifyOf(anchor)
    if anchor:find("LEFT") then return "LEFT"
    elseif anchor:find("RIGHT") then return "RIGHT"
    else return "CENTER" end
end

local function ApplyLayout()
    local db = TW:GetDB()
    local container = TW.TankContainer
    if not container then return end
    if InCombatLockdown() then _pendingLayout = true; return end

    container:SetScale(db.frameScale or 1)
    local anchor = db.anchor or "LEFT"
    container:ClearAllPoints()
    container:SetPoint(anchor, UIParent, anchor, db.anchorX or 0, db.anchorY or 0)

    local hpTex = TW:ResolveTexture(db.healthTexture)

    for i = 1, MAX_TANKS do
        local f = TW.TankFrames[i]
        if not f then break end

        f:SetSize(db.frameWidth, db.frameHeight)
        f:ClearAllPoints()
        if i == 1 then
            f:SetPoint("TOP", container, "TOP", 0, 0)
        else
            local prev = TW.TankFrames[i - 1]
            local s = db.frameSpacing
            if db.growDirection == "UP" then
                f:SetPoint("BOTTOM", prev, "TOP", 0, s)
            else
                f:SetPoint("TOP", prev, "BOTTOM", 0, -s)
            end
        end

        if f.healthBar then
            f.healthBar:SetStatusBarTexture(hpTex)
            if f.healthBar.bg then
                f.healthBar.bg:SetColorTexture(0.1, 0.1, 0.1, db.healthBackgroundAlpha or 0.35)
            end
        end

        if f.nameText then
            f.nameText:ClearAllPoints()
            local a = db.nameAnchor
            if not VALID_ANCHOR9[a] then a = "LEFT"; db.nameAnchor = a end
            f.nameText:SetPoint(a, f.healthBar, a, db.nameX or 0, db.nameY or 0)
            f.nameText:SetJustifyH(justifyOf(a))
        end
        if f.healthText then
            f.healthText:ClearAllPoints()
            local a = db.healthTextAnchor
            if not VALID_ANCHOR9[a] then a = "RIGHT"; db.healthTextAnchor = a end
            f.healthText:SetPoint(a, f.healthBar, a, db.healthTextX or 0, db.healthTextY or 0)
            f.healthText:SetJustifyH(justifyOf(a))
        end

        if TW.LayoutAuras then TW.LayoutAuras(f, db) end
    end
end
TW.ApplyLayout = ApplyLayout

-- ============================================================
-- UPDATE
-- ============================================================
local function UpdateFrame(f)
    if not f or not f._unit then return end
    local db = TW:GetDB()
    local unit = f._unit

    -- Name
    if f.nameText then
        if db.showName then
            local n = pcall(UnitName, unit)
            local ok, name = pcall(UnitName, unit)
            if not ok or not name then name = "?" end
            local maxLen = db.nameMaxLength or 0
            if maxLen > 0 and #name > maxLen then name = name:sub(1, maxLen) end
            f.nameText:SetText(name)
            f.nameText:Show()
        else
            f.nameText:Hide()
        end
    end

    -- HP
    local cur, max = 0, 0
    pcall(function()
        cur = UnitHealth(unit) or 0
        max = UnitHealthMax(unit) or 0
    end)
    if f.healthBar and max > 0 then
        f.healthBar:SetMinMaxValues(0, max)
        f.healthBar:SetValue(cur)
    end
    if f.healthText then
        if db.showHealthText and max > 0 then
            f.healthText:SetText(formatHP(cur, max, db.healthTextFormat))
            f.healthText:Show()
        else
            f.healthText:Hide()
        end
    end

    -- Color
    if f.healthBar then
        local r, g, b
        if db.healthColorMode == "STATIC" then
            local c = db.healthStaticColor or {r=0.2,g=0.6,b=0.2}
            r, g, b = c.r, c.g, c.b
        elseif db.healthColorMode == "REACTION" then
            r, g, b = 0.2, 0.7, 0.2
        else
            r, g, b = classColor(unit)
        end
        f.healthBar:SetStatusBarColor(r, g, b)
    end

    if TW.UpdateAuras then TW.UpdateAuras(f) end
end

local function RefreshAll()
    if not TW.TankContainer then return end
    ApplyLayout()
    if TW.ApplyFonts then TW:ApplyFonts() end
    for i = 1, MAX_TANKS do
        local f = TW.TankFrames[i]
        if f and f:IsShown() then UpdateFrame(f) end
    end
end
TW.RefreshAll = RefreshAll

-- ============================================================
-- TANK LIST REFRESH (call when roster / roles change)
-- ============================================================
function TW:RefreshTanks()
    if InCombatLockdown() then _pendingLayout = true; return end
    local units = collectTankUnits()
    for i = 1, MAX_TANKS do
        local f = TW.TankFrames[i]
        if not f then break end
        local unit = units[i]
        if unit and not f._testMode then
            f._unit = unit
            f:SetAttribute("unit", unit)
            f:Show()
            UpdateFrame(f)
        elseif not f._testMode then
            f._unit = nil
            f:SetAttribute("unit", nil)
            f:Hide()
        end
    end
    ApplyLayout()
end

-- ============================================================
-- MOVER
-- ============================================================
local moverShown
function TW:ToggleMover()
    if InCombatLockdown() then print("|cff00ff96TankWatch:|r combat lockdown"); return end
    local container = TW.TankContainer
    if not container then return end
    if not container._mover then
        local m = CreateFrame("Frame", nil, container, "BackdropTemplate")
        m:SetAllPoints(container)
        m:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        m:SetBackdropColor(0, 1, 0.3, 0.3)
        m:EnableMouse(true)
        m:SetMovable(true)
        m:RegisterForDrag("LeftButton")
        local fs = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        fs:SetPoint("CENTER")
        fs:SetText("TankWatch")
        m:SetScript("OnDragStart", function() container:SetMovable(true); container:StartMoving() end)
        m:SetScript("OnDragStop", function()
            container:StopMovingOrSizing()
            local point, _, _, x, y = container:GetPoint()
            local db = TW:GetDB()
            db.anchor = point; db.anchorX = math.floor(x + 0.5); db.anchorY = math.floor(y + 0.5)
            ApplyLayout()
        end)
        container._mover = m
    end
    if moverShown then container._mover:Hide() else container._mover:Show() end
    moverShown = not moverShown
end

-- ============================================================
-- TEST MODE
-- ============================================================
local TEST_NAMES = { "Tankzilla", "Smashbro", "Brickwall", "Ironhide", "Stonewall", "Wallcrusher", "Beefcake", "Bouldermane" }
local TEST_CLASSES = { "WARRIOR", "PALADIN", "DEATHKNIGHT", "DRUID", "MONK", "DEMONHUNTER", "WARRIOR", "PALADIN" }

function TW:SetTestMode(count)
    count = math.max(0, math.min(MAX_TANKS, count or 0))
    for i = 1, MAX_TANKS do
        local f = TW.TankFrames[i]
        if not f then break end
        if i <= count then
            f._testMode = true
            f._unit = nil
            f:SetAttribute("unit", nil)
            f:Show()
            local cls = TEST_CLASSES[i] or "WARRIOR"
            local c = CLASS_COLORS[cls] or { r=0.5, g=0.5, b=0.5 }
            if f.nameText then
                f.nameText:SetText(TEST_NAMES[i] or ("Tank" .. i))
                f.nameText:SetTextColor(c.r, c.g, c.b)
                f.nameText:Show()
            end
            if f.healthBar then
                f.healthBar:SetMinMaxValues(0, 1000)
                f.healthBar:SetValue(math.random(400, 950))
                f.healthBar:SetStatusBarColor(c.r, c.g, c.b)
            end
            if f.healthText then
                local pct = math.floor(f.healthBar:GetValue() / 1000 * 100)
                f.healthText:SetText(pct .. "%")
                f.healthText:Show()
            end
            if TW.SetTestAuras then TW.SetTestAuras(f, i) end
        else
            f._testMode = false
            f:Hide()
            f._unit = nil
            f:SetAttribute("unit", nil)
        end
    end
    ApplyLayout()
    if TW.ApplyFonts then TW:ApplyFonts() end
end

-- ============================================================
-- EVENTS
-- ============================================================
local ev = CreateFrame("Frame")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_ROLES_ASSIGNED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("UNIT_HEALTH")
ev:RegisterEvent("UNIT_MAXHEALTH")
ev:RegisterEvent("UNIT_AURA")
ev:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_REGEN_ENABLED" then
        if _pendingLayout then _pendingLayout = false; ApplyLayout() end
        TW:RefreshTanks()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "PLAYER_ENTERING_WORLD" then
        TW:RefreshTanks()
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_AURA" then
        for i = 1, MAX_TANKS do
            local f = TW.TankFrames[i]
            if f and f._unit == unit then UpdateFrame(f); break end
        end
    end
end)
