local addonName, TW = ...

local CreateFrame = CreateFrame
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitName, UnitClass, UnitExists = UnitName, UnitClass, UnitExists
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local IsInRaid, IsInGroup = IsInRaid, IsInGroup
local GetNumGroupMembers = GetNumGroupMembers
local format = string.format
local AbbreviateNumbers = AbbreviateNumbers

local MAX_TANKS = TW.MAX_TANKS

local _pendingLayout = false

-- Secret-value detection (12.0). issecretvalue is a global Blizzard fn.
local issecretvalue = _G.issecretvalue
local function isSecret(v)
    if issecretvalue then return issecretvalue(v) end
    return false
end



-- Forward declaration (defined further down) so EnsureCreated can call it.
local startRangeTicker

-- ============================================================
-- TANK DETECTION
-- ============================================================
local function isMyTankSpec()
    local spec = GetSpecialization and GetSpecialization()
    if not spec then return false end
    local role
    if GetSpecializationRole then
        local ok, r = pcall(GetSpecializationRole, spec)
        if ok then role = r end
    end
    return role == "TANK"
end

local function alreadyContains(units, unit)
    for _, u in ipairs(units) do
        if u == unit then return true end -- same regular unit token
        local ok, same = pcall(UnitIsUnit, u, unit)
        if ok and same ~= nil and not isSecret(same) and same == true then
            return true
        end
    end
    return false
end

local function isTankByRole(unit)
    local ok, r = pcall(UnitGroupRolesAssigned, unit)
    if not ok or r == nil or isSecret(r) then return false end
    return r == "TANK"
end

local function isMainTank(unit)
    if not GetPartyAssignment then return false end
    local ok, r = pcall(GetPartyAssignment, "MAINTANK", unit)
    if not ok or r == nil or isSecret(r) then return false end
    return r == 1 or r == true
end

local function isTankUnit(unit, mode)
    if mode == "MAINTANK" then return isMainTank(unit)
    elseif mode == "BOTH" then return isMainTank(unit) or isTankByRole(unit)
    else                        return isTankByRole(unit) end
end

function TW:PrintRosterDebug()
    print("|cff00ff96TankWatch:|r " .. (TW.L and TW.L["roster diagnostic:"] or "roster diagnostic:"))
    local function dump(u)
        if not UnitExists(u) then return end
        local name = "?"
        pcall(function() name = UnitName(u) or "?" end)
        local role = "?"
        pcall(function() role = UnitGroupRolesAssigned(u) or "?" end)
        local mt = false
        if GetPartyAssignment then
            pcall(function() mt = (GetPartyAssignment("MAINTANK", u) == 1) end)
        end
        print(string.format("  %s = |cffffffff%s|r | role=|cffffff00%s|r | /maintank=|cffffff00%s|r",
            u, tostring(name), tostring(role), tostring(mt)))
    end
    if IsInRaid() then
        local n = GetNumGroupMembers()
        print(string.format("  raid (%d):", n))
        for i = 1, n do dump("raid" .. i) end
    elseif IsInGroup() then
        print("  party:")
        dump("player")
        for i = 1, 4 do dump("party" .. i) end
    else
        print("  solo")
        dump("player")
    end
end

local function collectTankUnits()
    local db   = TW:GetDB()

    -- Visibility scope: hide everything if the current group state doesn't
    -- match what the user wants to see frames in.
    local vis = db.visibilityMode or "GROUP"
    if vis == "RAID"  and not IsInRaid()  then return {} end
    if vis == "GROUP" and not IsInGroup() then return {} end

    local mode = db.tankDetection or "ROLE"
    -- /maintank only exists in raids — auto-fallback to ROLE in 5-man
    if mode == "MAINTANK" and not IsInRaid() then mode = "ROLE" end

    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid" .. i
            if UnitExists(u) and isTankUnit(u, mode) then
                units[#units + 1] = u
            end
        end
    elseif IsInGroup() then
        if isTankUnit("player", mode) then units[#units + 1] = "player" end
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) and isTankUnit(u, mode) then
                units[#units + 1] = u
            end
        end
    else
        if isTankUnit("player", mode) then units[#units + 1] = "player" end
    end

    -- Force-include self if my spec is tank (RL forgot to assign me)
    if db.forceIncludeSelf and isMyTankSpec() and not alreadyContains(units, "player") then
        local me = "player"
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local ru = "raid" .. i
                local ok, same = pcall(UnitIsUnit, ru, "player")
                if ok and same then me = ru; break end
            end
        end
        table.insert(units, 1, me)
    end

    -- Force-include named players, if any are in the group
    local names = db.forceIncludeNames
    if names and next(names) then
        local lower = {}
        for n in pairs(names) do lower[n:lower()] = true end

        local function tryAdd(unit)
            if not UnitExists(unit) or alreadyContains(units, unit) then return end
            local ok, name = pcall(UnitName, unit)
            if not ok or not name or isSecret(name) then return end
            if lower[name:lower()] then
                units[#units + 1] = unit
            end
        end

        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do tryAdd("raid" .. i) end
        elseif IsInGroup() then
            tryAdd("player")
            for i = 1, 4 do tryAdd("party" .. i) end
        end
    end

    return units
end

-- ============================================================
-- COLOR HELPERS
-- ----------------------------------------------------------------
-- RAID_CLASS_COLORS is a "secret value" in WoW 12.0 / Midnight —
-- touching its fields taints execution. We use hardcoded literals
-- (the public class color values) so we never read a secret value.
-- ============================================================
local CLASS_COLORS = {
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
    DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
    DRUID       = { r = 1.00, g = 0.49, b = 0.04 },
    EVOKER      = { r = 0.20, g = 0.58, b = 0.50 },
    HUNTER      = { r = 0.67, g = 0.83, b = 0.45 },
    MAGE        = { r = 0.25, g = 0.78, b = 0.92 },
    MONK        = { r = 0.00, g = 1.00, b = 0.59 },
    PALADIN     = { r = 0.96, g = 0.55, b = 0.73 },
    PRIEST      = { r = 1.00, g = 1.00, b = 1.00 },
    ROGUE       = { r = 1.00, g = 0.96, b = 0.41 },
    SHAMAN      = { r = 0.00, g = 0.44, b = 0.87 },
    WARLOCK     = { r = 0.53, g = 0.53, b = 0.93 },
    WARRIOR     = { r = 0.78, g = 0.61, b = 0.43 },
}

local function classColor(unit)
    local ok, _, cls = pcall(UnitClass, unit)
    if not ok or not cls or isSecret(cls) then return 0.5, 0.5, 0.5 end
    local c = CLASS_COLORS[cls]
    if c then return c.r, c.g, c.b end
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
    container:SetClampedToScreen(true)
    TW.TankContainer = container

    for i = 1, MAX_TANKS do
        TW.TankFrames[i] = CreateTankFrame(i)
        TW.TankFrames[i]:SetParent(container)
    end
    startRangeTicker()
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
            local ok, name = pcall(UnitName, unit)
            if not ok or not name then name = "?" end
            -- Don't compute length on a secret string (#secret taints).
            if not isSecret(name) then
                local maxLen = db.nameMaxLength or 0
                if maxLen > 0 and #name > maxLen then name = name:sub(1, maxLen) end
            end
            f.nameText:SetText(name)
            f.nameText:Show()
        else
            f.nameText:Hide()
        end
    end

    -- HP
    -- 12.0: UnitHealth on group members returns a SECRET number. Bar
    -- handles it (SetValue accepts secrets). For text, we use
    -- AbbreviateNumbers (Blizzard C function that accepts secret input
    -- and returns a regular display string). PERCENT format can't be
    -- computed (would need cur/max arithmetic) → falls back to absolute.
    local cur, max
    pcall(function()
        cur = UnitHealth(unit)
        max = UnitHealthMax(unit) or 0
    end)
    if f.healthBar and max and max > 0 then
        f.healthBar:SetMinMaxValues(0, max)
        if cur ~= nil then
            pcall(f.healthBar.SetValue, f.healthBar, cur)
        else
            f.healthBar:SetValue(0)
        end
    end
    if f.healthText then
        if db.showHealthText and cur ~= nil and max and max > 0 then
            -- Migrate legacy PERCENT / CURRENT_PERCENT (no longer feasible
            -- on live units in 12.0) to CURRENT.
            local fmt = db.healthTextFormat
            if fmt == "PERCENT" or fmt == "CURRENT_PERCENT" or not fmt then
                fmt = "CURRENT"
                db.healthTextFormat = fmt
            end
            if not isSecret(cur) and not isSecret(max) then
                f.healthText:SetText(formatHP(cur, max, fmt))
            else
                local curStr
                if AbbreviateNumbers then
                    pcall(function() curStr = AbbreviateNumbers(cur) end)
                end
                if not curStr then curStr = "?" end
                if fmt == "CURRENT_MAX" then
                    local maxStr = AbbreviateNumbers and AbbreviateNumbers(max) or tostring(max)
                    f.healthText:SetText(curStr .. " / " .. maxStr)
                else -- CURRENT
                    f.healthText:SetText(curStr)
                end
            end
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
        if f and f:IsShown() then
            if f._testMode then
                if TW._applyTestFrameSettings then TW._applyTestFrameSettings(f, i) end
            else
                UpdateFrame(f)
            end
        end
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
-- Snap-to-edge: if container ends within SNAP px of an edge, anchor to that edge.
-- Otherwise stay centered on that axis (with offset from center).
local SNAP_DIST = 16
local function snapAndStore(container)
    local left   = container:GetLeft()
    local bottom = container:GetBottom()
    if not left or not bottom then return end
    local w, h = container:GetWidth(), container:GetHeight()
    local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
    local dRight = pw - (left + w)
    local dTop   = ph - (bottom + h)

    local hPart, vPart = "", ""
    if left   < SNAP_DIST then hPart = "LEFT"
    elseif dRight < SNAP_DIST then hPart = "RIGHT" end
    if dTop    < SNAP_DIST then vPart = "TOP"
    elseif bottom < SNAP_DIST then vPart = "BOTTOM" end

    local anchor
    if hPart == "" and vPart == "" then anchor = "CENTER"
    elseif hPart == ""               then anchor = vPart
    elseif vPart == ""               then anchor = hPart
    else                                  anchor = vPart .. hPart end

    local x, y = 0, 0
    if hPart == "" then x = (left + w / 2) - pw / 2 end
    if vPart == "" then y = (bottom + h / 2) - ph / 2 end

    local db = TW:GetDB()
    db.anchor  = anchor
    db.anchorX = math.floor(x + 0.5)
    db.anchorY = math.floor(y + 0.5)
end

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
            snapAndStore(container)
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

-- per-frame interpolation toward a random target → fluid test animation
local function pickTestTarget(f)
    local cur = f._testHP or 700
    local t = cur + math.random(-260, 260)
    if t < 150 then t = 150 + math.random(0, 100) end
    if t > 1000 then t = 850 + math.random(0, 150) end
    f._testHPTarget = t
end

-- Apply current settings to a single test frame: respects showName,
-- showHealthText, showAuras, healthColorMode, healthStaticColor.
local function applyTestFrameSettings(f, idx)
    if not f or not f._testMode then return end
    local db  = TW:GetDB()
    local cls = TEST_CLASSES[idx] or "WARRIOR"
    local c   = CLASS_COLORS[cls] or { r = 0.5, g = 0.5, b = 0.5 }

    if f.nameText then
        if db.showName then
            f.nameText:SetText(TEST_NAMES[idx] or ("Tank" .. idx))
            f.nameText:SetTextColor(1, 1, 1)
            f.nameText:Show()
        else
            f.nameText:Hide()
        end
    end

    if f.healthBar then
        local r, g, b
        if db.healthColorMode == "STATIC" then
            local sc = db.healthStaticColor or { r = 0.2, g = 0.6, b = 0.2 }
            r, g, b = sc.r, sc.g, sc.b
        elseif db.healthColorMode == "REACTION" then
            r, g, b = 0.2, 0.7, 0.2
        else
            r, g, b = c.r, c.g, c.b
        end
        f.healthBar:SetStatusBarColor(r, g, b)
    end

    if f.healthText then
        if db.showHealthText then f.healthText:Show() else f.healthText:Hide() end
    end

    if TW.SetTestAuras then TW.SetTestAuras(f, idx) end
end
TW._applyTestFrameSettings = applyTestFrameSettings

function TW:SetTestMode(count)
    if InCombatLockdown() then
        print("|cff00ff96TankWatch:|r " .. (TW.L and TW.L["combat lockdown"] or "combat lockdown"))
        return
    end
    count = math.max(0, math.min(MAX_TANKS, count or 0))
    for i = 1, MAX_TANKS do
        local f = TW.TankFrames[i]
        if not f then break end
        if i <= count then
            f._testMode = true
            f._unit = nil
            f:SetAttribute("unit", nil)
            f:Show()
            if f.healthBar then
                f.healthBar:SetMinMaxValues(0, 1000)
                local initial = math.random(400, 950)
                f.healthBar:SetValue(initial)
                -- Seed _testHP with the regular number directly. NEVER read
                -- from f.healthBar:GetValue() — if this frame previously
                -- displayed a live unit, the bar may still hold a secret
                -- value left over from UnitHealth, which would taint us.
                f._testHP       = initial
                f._testHPTarget = initial
            end
            applyTestFrameSettings(f, i)
        else
            f._testMode = false
            f:Hide()
            f._unit = nil
            f:SetAttribute("unit", nil)
        end
    end
    ApplyLayout()
    if TW.ApplyFonts then TW:ApplyFonts() end

    -- Spawn / refresh the test ticker (every frame; smooth interpolation)
    if not TW._testTicker then
        TW._testTicker = CreateFrame("Frame")
        TW._testTicker._acc = 0
        TW._testTicker:SetScript("OnUpdate", function(self, elapsed)
            self._acc = (self._acc or 0) + elapsed
            local pickNew = self._acc >= 0.5
            if pickNew then self._acc = 0 end

            local anyTest = false
            local db = TW:GetDB()
            for i = 1, MAX_TANKS do
                local f = TW.TankFrames[i]
                if f and f._testMode and f.healthBar then
                    anyTest = true
                    -- Use ONLY regular numbers; never re-read from healthBar:GetValue
                    f._testHP       = f._testHP       or 700
                    f._testHPTarget = f._testHPTarget or f._testHP
                    if pickNew then pickTestTarget(f) end

                    -- exponential ease toward target (rate ~6/s)
                    local rate   = 6 * elapsed
                    if rate > 1 then rate = 1 end
                    local cur    = f._testHP
                    local target = f._testHPTarget
                    cur = cur + (target - cur) * rate
                    f._testHP = cur

                    f.healthBar:SetValue(cur)
                    if f.healthText and db.showHealthText then
                        f.healthText:SetText(formatHP(cur, 1000, db.healthTextFormat))
                    end
                end
            end
            if not anyTest then self:Hide() end
        end)
    end
    local anyTest = false
    for i = 1, MAX_TANKS do
        if TW.TankFrames[i] and TW.TankFrames[i]._testMode then anyTest = true; break end
    end
    if anyTest then TW._testTicker:Show() else TW._testTicker:Hide() end
end

-- ============================================================
-- RANGE FADE (poll every 0.4s — UnitInRange is the right API)
-- ============================================================
-- Range fade is DISABLED in WoW 12.0 / Midnight: UnitInRange returns a
-- secret-tagged boolean. Comparing or branching on a secret-tagged value
-- taints execution. Per the project no-secret-workarounds rule, the feature
-- stays defined in defaults (so a future Blizzard fix re-enables it without
-- a config wipe) but the ticker always sets alpha=1 on real units.
function startRangeTicker()
    if TW._rangeTicker then return end
    local t = CreateFrame("Frame")
    t._acc = 0
    t:SetScript("OnUpdate", function(self, elapsed)
        self._acc = (self._acc or 0) + elapsed
        if self._acc < 1 then return end
        self._acc = 0
        for i = 1, MAX_TANKS do
            local f = TW.TankFrames[i]
            if f and f:IsShown() then f:SetAlpha(1) end
        end
    end)
    TW._rangeTicker = t
end

-- ============================================================
-- EVENTS
-- ============================================================
local ev = CreateFrame("Frame")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_ROLES_ASSIGNED")
ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("UNIT_HEALTH")
ev:RegisterEvent("UNIT_MAXHEALTH")
ev:RegisterEvent("UNIT_AURA")
ev:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_REGEN_ENABLED" then
        if _pendingLayout then _pendingLayout = false; ApplyLayout() end
        TW:RefreshTanks()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED"
        or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        TW:RefreshTanks()
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_AURA" then
        for i = 1, MAX_TANKS do
            local f = TW.TankFrames[i]
            if f and f._unit == unit then UpdateFrame(f); break end
        end
    end
end)
