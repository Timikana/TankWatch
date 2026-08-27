local addonName, TW = ...

local CreateFrame = CreateFrame
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitName, UnitClass, UnitExists = UnitName, UnitClass, UnitExists
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitPower, UnitPowerMax, UnitPowerType = UnitPower, UnitPowerMax, UnitPowerType
local IsInRaid, IsInGroup = IsInRaid, IsInGroup

-- Class icon texcoords on the standard 4x4 atlas
local CLASS_ICON_TEX = "Interface\\TargetingFrame\\UI-Classes-Circles"
local CLASS_ICON_COORDS = {
    WARRIOR     = {0.00, 0.25, 0.00, 0.25},
    MAGE        = {0.25, 0.50, 0.00, 0.25},
    ROGUE       = {0.50, 0.75, 0.00, 0.25},
    DRUID       = {0.75, 1.00, 0.00, 0.25},
    HUNTER      = {0.00, 0.25, 0.25, 0.50},
    SHAMAN      = {0.25, 0.50, 0.25, 0.50},
    PRIEST      = {0.50, 0.75, 0.25, 0.50},
    WARLOCK     = {0.75, 1.00, 0.25, 0.50},
    PALADIN     = {0.00, 0.25, 0.50, 0.75},
    DEATHKNIGHT = {0.25, 0.50, 0.50, 0.75},
    MONK        = {0.50, 0.75, 0.50, 0.75},
    DEMONHUNTER = {0.75, 1.00, 0.50, 0.75},
    EVOKER      = {0.00, 0.25, 0.75, 1.00},
}

-- Power-type RGB lookup (Enum.PowerType in 12.0). Hardcoded because
-- Blizzard's PowerBarColor table can be secret-tagged.
local POWER_COLORS = {
    [0]  = { r = 0,    g = 0,    b = 1    },  -- Mana
    [1]  = { r = 1,    g = 0,    b = 0    },  -- Rage
    [2]  = { r = 1,    g = 0.5,  b = 0.25 },  -- Focus
    [3]  = { r = 1,    g = 1,    b = 0    },  -- Energy
    [6]  = { r = 0,    g = 0.82, b = 1    },  -- Runic Power
    [8]  = { r = 0.3,  g = 0.45, b = 0.85 },  -- Lunar Power
    [11] = { r = 0,    g = 0.5,  b = 1    },  -- Maelstrom
    [13] = { r = 0.74, g = 0.36, b = 0.98 },  -- Insanity
    [17] = { r = 0.78, g = 0.26, b = 0.99 },  -- Fury (DH)
    [18] = { r = 1,    g = 0.61, b = 0    },  -- Pain (DH)
}
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



-- Forward declarations (defined further down). Needed when an earlier
-- function (e.g. ApplyLayout) references one of these — without this,
-- the name resolves as a global at compile time → nil at runtime.
local startRangeTicker
local updateRaidTargetIcon

-- ============================================================
-- TANK DETECTION
-- ============================================================
local function isMyTankSpec()
    local spec
    pcall(function() spec = GetSpecialization and GetSpecialization() end)
    if isSecret(spec) then return false end
    if spec == nil then return false end
    local r
    if GetSpecializationRole then
        pcall(function() r = GetSpecializationRole(spec) end)
    end
    -- MoP Classic has GetSpecializationInfo(specIndex) returning role at idx 5
    if (r == nil or r == "") and GetSpecializationInfo then
        pcall(function() local _, _, _, _, role = GetSpecializationInfo(spec); r = role end)
    end
    if isSecret(r) then return false end
    if r == nil then return false end
    return r == "TANK"
end

local function alreadyContains(units, unit)
    for _, u in ipairs(units) do
        if u == unit then return true end -- same regular unit token
        local ok, same = pcall(UnitIsUnit, u, unit)
        if ok and not isSecret(same) and same == true then
            return true
        end
    end
    return false
end

local function isTankByRole(unit)
    local ok, r = pcall(UnitGroupRolesAssigned, unit)
    if not ok then return false end
    if isSecret(r) then return false end -- ALWAYS check secret BEFORE any comparison
    if r == "TANK" then return true end
    -- Classic-era fallback: UnitGroupRolesAssigned often returns "NONE" or ""
    -- on Classic clients (role isn't auto-derived from spec like on retail).
    -- For the player itself we can read the spec role directly. Other party
    -- members would need an Inspect — skip; users can rely on /maintank.
    if r == nil or r == "" or r == "NONE" then
        local isPlayer
        pcall(function() isPlayer = UnitIsUnit(unit, "player") end)
        if isPlayer == true and isMyTankSpec() then return true end
    end
    return false
end

local function isMainTank(unit)
    if not GetPartyAssignment then return false end
    local ok, r = pcall(GetPartyAssignment, "MAINTANK", unit)
    if not ok then return false end
    if isSecret(r) then return false end
    if r == nil then return false end
    return r == 1 or r == true
end

local function isTankUnit(unit, mode)
    if mode == "MAINTANK" then return isMainTank(unit)
    elseif mode == "BOTH" then return isMainTank(unit) or isTankByRole(unit)
    else                        return isTankByRole(unit) end
end

function TW:PrintRosterDebug()
    print("|cff00ff96TankWatch:|r " .. (TW.L and TW.L["roster diagnostic:"] or "roster diagnostic:"))
    -- Spec/role detection summary for the player (Classic fallback path)
    local spec, specName, specRole, gsr
    pcall(function() spec = GetSpecialization and GetSpecialization() end)
    if spec and GetSpecializationInfo then
        pcall(function() local _, n, _, _, role = GetSpecializationInfo(spec); specName, specRole = n, role end)
    end
    if spec and GetSpecializationRole then
        pcall(function() gsr = GetSpecializationRole(spec) end)
    end
    print(string.format("  player spec: |cffffff00idx=%s|r |cffffffffname=%s|r role(SpecInfo)=|cffffff00%s|r role(SpecRole)=|cffffff00%s|r isMyTankSpec()=|cffffff00%s|r",
        tostring(spec), tostring(specName), tostring(specRole), tostring(gsr), tostring(isMyTankSpec())))
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
        -- Solo. With visibilityMode = "ALWAYS" the user explicitly opted in
        -- to seeing the frame outside groups — show them even when role
        -- detection fails (Classic has no LFG role autodetect, and
        -- GetSpecialization returns nil on some MoP Classic builds).
        if vis == "ALWAYS" then
            units[#units + 1] = "player"
        elseif isTankUnit("player", mode) or isMyTankSpec() then
            units[#units + 1] = "player"
        end
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
            if not ok then return end
            if isSecret(name) then return end -- can't lower-case a secret string
            if name == nil then return end
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

-- Apply the bg fill (texture-tint or solid) using the chosen color mode.
-- testClassKey is the hardcoded class name for test frames (no unit).
local function applyBackgroundFill(f, db, unit, testClassKey)
    if not f.healthBar or not f.healthBar.bg then return end
    local bc
    if db.backgroundColorMode == "CLASS" then
        local r, g, b
        if testClassKey then
            local c = CLASS_COLORS[testClassKey] or { r = 0.5, g = 0.5, b = 0.5 }
            r, g, b = c.r, c.g, c.b
        else
            r, g, b = classColor(unit)
        end
        bc = { r = r, g = g, b = b }
    else
        bc = db.healthBackgroundColor or { r = 0.1, g = 0.1, b = 0.1 }
    end
    local a = db.healthBackgroundAlpha or 0.35
    local bgTex = db.healthBackgroundTexture
    if db.useBackgroundTexture and bgTex and bgTex ~= "" then
        f.healthBar.bg:SetVertexColor(bc.r, bc.g, bc.b, a)
    else
        f.healthBar.bg:SetColorTexture(bc.r, bc.g, bc.b, a)
    end
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
    -- Click actions (BW pattern):
    --   LeftClick           → target
    --   RightClick          → Blizzard unit menu (contains Set Focus + Raid Target submenu)
    --   Shift+LeftClick     → cycle raid target marker (1..8..0)
    --   Ctrl+LeftClick      → set focus
    -- All gated behind db.clickActions (default true). Modifiers re-applied
    -- on roster refresh because SetAttribute is combat-locked.
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    f:RegisterForClicks("AnyDown")
    f.applyClickActions = function()
        if InCombatLockdown() then return false end
        local db = TW:GetDB()
        local unit = f._unit or ("raid" .. index)
        if db.clickActions ~= false then
            f:SetAttribute("shift-type1", "macro")
            f:SetAttribute("shift-macrotext1",
                ("/run local i=GetRaidTargetIndex('%s') or 0; if i>=8 then i=0 end; SetRaidTarget('%s', i+1)"):format(unit, unit))
            f:SetAttribute("ctrl-type1", "focus")
        else
            f:SetAttribute("shift-type1", nil)
            f:SetAttribute("shift-macrotext1", nil)
            f:SetAttribute("ctrl-type1", nil)
        end
        return true
    end
    f.applyClickActions()
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

    -- Absorb shield overlay (DandersFrames-style). Same area as the health bar;
    -- StatusBar:SetValue accepts secret values, so we can pass UnitGetTotalAbsorbs
    -- directly. SetMinMaxValues(0, UnitHealthMax) gives a relative size.
    local abs = CreateFrame("StatusBar", nil, hp)
    abs:SetAllPoints(hp)
    abs:SetStatusBarTexture("Interface\\RaidFrame\\Shield-Fill")
    abs:SetMinMaxValues(0, 1)
    abs:SetValue(0)
    -- SetReverseFill is toggled per-frame in ApplyLayout based on db.absorbBarSide
    abs:SetFrameLevel(hp:GetFrameLevel() + 4)
    abs:Hide()
    f.absorbBar = abs

    -- Power bar (rage / mana / runic power / etc.) — pinned at the BOTTOM
    -- of the frame; healthBar's bottom is shifted up to make room when shown.
    local pp = CreateFrame("StatusBar", nil, f)
    pp:Hide()
    f.powerBar = pp

    local ppBg = pp:CreateTexture(nil, "BACKGROUND")
    ppBg:SetAllPoints(pp)
    ppBg:SetColorTexture(0.04, 0.04, 0.04, 0.65)
    pp.bg = ppBg

    -- Text overlay frame: sits ABOVE the absorb bar so name + HP text are
    -- never hidden by the shield overlay.
    local textLayer = CreateFrame("Frame", nil, hp)
    textLayer:SetAllPoints(hp)
    textLayer:SetFrameLevel(abs:GetFrameLevel() + 1)
    f.textLayer = textLayer

    -- Name + HP text (parented to textLayer so they render on top of absorb)
    local nameText = textLayer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetTextColor(1, 1, 1)
    f.nameText = nameText

    local hpText = textLayer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hpText:SetTextColor(0.95, 0.95, 0.95)
    f.healthText = hpText

    -- Power text (parented to the powerBar's OVERLAY so it draws ON TOP of
    -- the bar fill, not behind it).
    local ppText = pp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ppText:SetTextColor(0.92, 0.92, 0.92)
    f.powerText = ppText

    -- Class icon (used in compact mode)
    local classIcon = f:CreateTexture(nil, "ARTWORK")
    classIcon:SetTexture(CLASS_ICON_TEX)
    classIcon:Hide()
    f.classIcon = classIcon

    -- Raid target marker icon — hosted on a dedicated child Frame whose
    -- FrameLevel sits ABOVE every other child Frame (healthBar, powerBar,
    -- absorbBar, aura buttons). A texture parented to `f` alone would be
    -- buried under those child Frames, regardless of OVERLAY sublevel,
    -- because child Frames draw above the parent's layers. BW skirts this
    -- by parenting the texture to healthBar, but TW's compact mode hides
    -- the healthBar — so a separate always-shown host is the clean fix.
    local rtHost = CreateFrame("Frame", nil, f)
    rtHost:SetAllPoints(f)
    rtHost:SetFrameLevel((f:GetFrameLevel() or 1) + 50)
    f.raidTargetHost = rtHost
    local rt = rtHost:CreateTexture(nil, "OVERLAY", nil, 7)
    rt:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    rt:SetSize(24, 24)
    rt:SetPoint("CENTER", rtHost, "CENTER", 0, 0)
    rt:Hide()
    f.raidTargetIcon = rt

    -- Death overlay: skull icon centered on the frame + dim. Hidden by
    -- default, shown by UpdateFrame when the tank is dead/ghost.
    local deadOverlay = f:CreateTexture(nil, "OVERLAY", nil, 7)
    deadOverlay:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8") -- skull
    deadOverlay:SetSize(24, 24)
    deadOverlay:SetPoint("CENTER", f, "CENTER", 0, 0)
    deadOverlay:Hide()
    f.deadOverlay = deadOverlay

    -- Selection / hover border — BossWatch pattern:
    --   1. Native HIGHLIGHT draw-layer texture for mouseover. Blizzard
    --      auto-shows it when the frame is moused over (zero events).
    --   2. BackdropTemplate child frame with edgeFile for target/focus.
    --      Cleaner than 4 manually-anchored strips, and the edge thickness
    --      is a single SetBackdrop call. Anchored -2/+2 outside f so the
    --      border sits AROUND the frame, not inside it.
    --   3. BOUNCE alpha animation for the pulse effect when active.
    local hover = f:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(f)
    hover:SetColorTexture(1, 1, 1, 0.15)
    f.hoverTexture = hover

    local hl = CreateFrame("Frame", nil, f, "BackdropTemplate")
    hl:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
    hl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
    hl:SetFrameLevel((f:GetFrameLevel() or 1) + 5)
    hl:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    hl:SetBackdropBorderColor(1, 0.82, 0, 1)
    hl:Hide()
    f.targetHighlight = hl

    local ag = hl:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetFromAlpha(1)
    a1:SetToAlpha(0.35)
    a1:SetDuration(0.7)
    a1:SetSmoothing("IN_OUT")
    hl._anim = ag

    f.refreshHighlight = function()
        local db = TW:GetDB()
        -- Hover texture: gated by master toggle + color from db.
        if db.showHighlight == false then
            hover:SetColorTexture(1, 1, 1, 0)  -- transparent → no visible hover
        else
            local hc = db.highlightHoverColor
            if type(hc) == "table" then
                hover:SetColorTexture(hc.r or 1, hc.g or 1, hc.b or 1, hc.a or 0.15)
            else
                hover:SetColorTexture(1, 1, 1, 0.15)
            end
        end
        -- Target/focus border frame
        if db.showHighlight == false or not f._unit then
            if hl._anim then hl._anim:Stop() end
            hl:Hide(); return
        end
        local thick = math.max(1, math.min(6, db.highlightThickness or 2))
        hl:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = thick,
        })
        local function colorFrom(key, dr, dg, db_, da)
            local c = db[key]
            if type(c) == "table" then
                return c.r or dr, c.g or dg, c.b or db_, c.a or da
            end
            return dr, dg, db_, da
        end
        local isTarget, isFocus
        pcall(function() isTarget = UnitIsUnit(f._unit, "target") end)
        pcall(function() isFocus  = UnitIsUnit(f._unit, "focus")  end)
        local r, g, b, a
        if isTarget == true then
            r, g, b, a = colorFrom("highlightTargetColor", 1, 0.82, 0, 1)
        elseif isFocus == true then
            r, g, b, a = colorFrom("highlightFocusColor", 0.3, 0.85, 1, 1)
        else
            if hl._anim then hl._anim:Stop() end
            hl:Hide(); return
        end
        hl:SetBackdropBorderColor(r, g, b, a)
        hl:SetAlpha(1)
        hl:Show()
        if db.highlightAnimate ~= false then
            if not hl._anim:IsPlaying() then hl._anim:Play() end
        else
            hl._anim:Stop()
        end
    end

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

    -- Off-screen rescue: if the saved position lands the container entirely
    -- outside the screen (e.g. the user dragged it on a wider resolution
    -- and is now on a smaller one), force-reset to the default anchor on
    -- the next frame once GetLeft/Right have resolved.
    C_Timer.After(0, function()
        if not container.GetLeft then return end
        local l, r = container:GetLeft(),   container:GetRight()
        local bt, t = container:GetBottom(), container:GetTop()
        local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
        if not (l and r and bt and t and pw and ph) then return end
        local off = (r < 0) or (l > pw) or (t < 0) or (bt > ph)
        if off then
            db.anchor, db.anchorX, db.anchorY = "LEFT", 50, 0
            container:ClearAllPoints()
            container:SetPoint("LEFT", UIParent, "LEFT", 50, 0)
            print("|cff00ff96TankWatch:|r " ..
                (TW.L["frame was off-screen — repositioned to LEFT 50,0"]
                 or "frame was off-screen — repositioned to LEFT 50,0"))
        end
    end)

    -- Resize the container to match the actual visible content so that the
    -- mover overlay (which uses :SetAllPoints(container)) covers exactly
    -- the tank frames and not extra empty space below.
    local shownCount = 0
    for i = 1, MAX_TANKS do
        local f = TW.TankFrames[i]
        if f and (f._unit or f._testMode) then shownCount = shownCount + 1 end
    end
    local h = (shownCount > 0)
        and (shownCount * db.frameHeight + (shownCount - 1) * db.frameSpacing)
        or db.frameHeight
    container:SetSize(db.frameWidth, h)

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

        -- Compact mode: hide health/power/absorb/text/name and show class icon
        local compact   = db.compactMode and true or false
        local hideHP    = compact or (db.showHealthBar == false)
        local pwH       = (not compact and db.showPowerBar and (db.powerBarHeight or 0)) or 0

        if f.bg then
            if compact then
                f.bg:SetColorTexture(0, 0, 0, 0)  -- transparent in compact
            else
                f.bg:SetColorTexture(0, 0, 0, 0.6)
            end
        end

        if f.healthBar then
            if hideHP then
                f.healthBar:Hide()
            else
                f.healthBar:Show()
                f.healthBar:ClearAllPoints()
                f.healthBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
                if pwH > 0 then
                    f.healthBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1 + pwH + 1)
                else
                    f.healthBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
                end
                f.healthBar:SetStatusBarTexture(hpTex)
                if f.healthBar.bg then
                    local bgTex = db.healthBackgroundTexture
                    if db.useBackgroundTexture and bgTex and bgTex ~= "" then
                        f.healthBar.bg:SetTexture(TW:ResolveTexture(bgTex))
                    end
                end
            end
        end

        -- Class icon: visible if compactMode + showClassIcon
        if f.classIcon then
            if compact and db.showClassIcon then
                local sz = db.classIconSize or 28
                f.classIcon:ClearAllPoints()
                f.classIcon:SetPoint("LEFT", f, "LEFT", 2, 0)
                f.classIcon:SetSize(sz, sz)
                f.classIcon:Show()
            else
                f.classIcon:Hide()
            end
        end

        -- Power bar — pinned to BOTTOM of the frame
        if f.powerBar then
            if pwH > 0 then
                f.powerBar:ClearAllPoints()
                f.powerBar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  1,  1)
                f.powerBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
                f.powerBar:SetHeight(pwH)
                f.powerBar:SetStatusBarTexture(TW:ResolveTexture(db.powerBarTexture or db.healthTexture))
                f.powerBar:Show()
            else
                f.powerBar:Hide()
            end
        end

        if f.absorbBar then
            local absTex = db.absorbBarTexture
            if absTex and absTex ~= "" then
                f.absorbBar:SetStatusBarTexture(TW:ResolveTexture(absTex))
            else
                f.absorbBar:SetStatusBarTexture([[Interface\RaidFrame\Shield-Fill]])
            end
            f.absorbBar:SetReverseFill(db.absorbBarSide ~= "LEFT")
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
        if f.powerText then
            f.powerText:ClearAllPoints()
            local a = db.powerTextAnchor
            if not VALID_ANCHOR9[a] then a = "RIGHT"; db.powerTextAnchor = a end
            local refBar = (pwH > 0) and f.powerBar or f.healthBar
            f.powerText:SetPoint(a, refBar, a, db.powerTextX or 0, db.powerTextY or 0)
            f.powerText:SetJustifyH(justifyOf(a))
        end

        if TW.LayoutAuras then TW.LayoutAuras(f, db) end
        if f._unit or f._testMode then updateRaidTargetIcon(f) end
    end
end
TW.ApplyLayout = ApplyLayout

-- Refresh the raid target icon on a single frame. Called from UpdateFrame
-- and from the RAID_TARGET_UPDATE event handler. Secret-safe: friendly
-- raid tokens return a regular number; for safety we still pcall both the
-- GetRaidTargetIndex call and the SetRaidTargetIconTexCoord (Blizzard C
-- function handles secret numbers internally).
-- Hardcoded texcoord table for the 8 raid markers on the standard
-- Interface\TargetingFrame\UI-RaidTargetingIcons sheet (4x4 atlas,
-- 8 used cells). Fallback when SetRaidTargetIconTexCoord is missing
-- or fails silently.
local RAID_ICON_COORDS = {
    [1] = {0.00, 0.25, 0.00, 0.25},  -- Star
    [2] = {0.25, 0.50, 0.00, 0.25},  -- Circle
    [3] = {0.50, 0.75, 0.00, 0.25},  -- Diamond
    [4] = {0.75, 1.00, 0.00, 0.25},  -- Triangle
    [5] = {0.00, 0.25, 0.25, 0.50},  -- Moon
    [6] = {0.25, 0.50, 0.25, 0.50},  -- Square
    [7] = {0.50, 0.75, 0.25, 0.50},  -- Cross
    [8] = {0.75, 1.00, 0.25, 0.50},  -- Skull
}

function updateRaidTargetIcon(f)  -- forward-declared local at top of file
    if not f or not f.raidTargetIcon then return end
    local db = TW:GetDB()
    if db.showRaidTargetIcon == false then f.raidTargetIcon:Hide(); return end
    -- Re-apply size + anchor every time so the configurable settings take
    -- effect without needing a /reload.
    local sz = db.raidTargetIconSize or 24
    local anchor = db.raidTargetIconAnchor or "CENTER"
    f.raidTargetIcon:SetSize(sz, sz)
    f.raidTargetIcon:ClearAllPoints()
    -- Anchor relative to the HOST frame (which mirrors f:SetAllPoints), so
    -- offsets are interpreted the same way as if anchored to f directly.
    local host = f.raidTargetHost or f
    f.raidTargetIcon:SetPoint(anchor, host, anchor,
        db.raidTargetIconX or 0, db.raidTargetIconY or 0)
    f.raidTargetIcon:SetAlpha(db.raidTargetIconAlpha or 0.9)
    f.raidTargetIcon:SetVertexColor(1, 1, 1, 1)
    local tex = f.raidTargetIcon

    -- Test mode: idx is a known Lua number, use the hardcoded texcoord path.
    if f._testMode then
        local idx = ((f._index or 1) - 1) % 8 + 1
        local c = RAID_ICON_COORDS[idx]
        if c then
            tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            tex:SetTexCoord(c[1], c[2], c[3], c[4])
            tex:Show()
        else
            tex:Hide()
        end
        return
    end

    -- Real mode: in Midnight 12.0 GetRaidTargetIndex returns a SECRET value
    -- (even for friendly units — confirmed via the "place la cible ??? sur X"
    -- chat where ??? is the secret marker name). DandersFrames pattern:
    --   1. Capture via pcall (the local gets the secret-tagged value)
    --   2. If issecretvalue → use the TEXTURE METHOD :SetSpriteSheetCell
    --      (accepts secret indices C-side, unlike the SetRaidTargetIconTexture global)
    --   3. Else if a regular number → use the global SetRaidTargetIconTexture
    --   4. Else → hide
    if not f._unit then tex:Hide(); return end
    local index
    pcall(function() index = GetRaidTargetIndex(f._unit) end)

    local issecret = _G.issecretvalue
    local canaccess = _G.canaccessvalue

    if issecret and issecret(index) then
        tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        pcall(function() tex:SetSpriteSheetCell(index, 4, 4, 64, 64) end)
        tex:Show()
    elseif index and (not canaccess or canaccess(index)) and index ~= 0 then
        tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        if SetRaidTargetIconTexture then
            pcall(SetRaidTargetIconTexture, tex, index)
        else
            local c = RAID_ICON_COORDS[index]
            if c then tex:SetTexCoord(c[1], c[2], c[3], c[4]) end
        end
        tex:Show()
    else
        tex:Hide()
    end
end

-- ============================================================
-- UPDATE
-- ============================================================
local function UpdateFrame(f)
    if not f or not f._unit then return end
    local db = TW:GetDB()
    local unit = f._unit

    -- Raid target marker (small Blizzard icon top-left of the frame)
    f._showRaidTargetIcon = db.showRaidTargetIcon ~= false
    updateRaidTargetIcon(f)

    -- Selection / hover border (target = gold, focus = cyan, hover = white)
    if f.refreshHighlight then f:refreshHighlight() end

    -- Death state: dim the frame + show a skull overlay so it's obvious
    -- the tank is down. Checked before anything else so the rest of the
    -- update still runs (HP bar to 0, etc.) but the visual cue dominates.
    local isDead
    pcall(function() isDead = UnitIsDeadOrGhost(unit) end)
    if isDead == true then
        f:SetAlpha(0.45)
        if f.deadOverlay then f.deadOverlay:Show() end
    else
        if not f._testMode then f:SetAlpha(1) end
        if f.deadOverlay then f.deadOverlay:Hide() end
    end

    -- Compact mode forces name/text/bars hidden regardless of individual toggles
    local compact = db.compactMode and true or false

    -- Class icon update (compact only). pcall(UnitClass) returns
    -- (success, localizedClass, englishClass) — we want the English token
    -- (3rd return) since CLASS_ICON_COORDS is keyed by "WARRIOR" / "PALADIN" etc.
    if f.classIcon and compact and db.showClassIcon then
        local ok, _, cls = pcall(UnitClass, unit)
        if not ok then cls = nil end
        if isSecret(cls) then cls = nil end
        if type(cls) == "string" and CLASS_ICON_COORDS[cls] then
            local c = CLASS_ICON_COORDS[cls]
            f.classIcon:SetTexCoord(c[1], c[2], c[3], c[4])
        end
    end

    -- Name
    if f.nameText then
        if compact then f.nameText:Hide()
        elseif db.showName then
            local ok, name = pcall(UnitName, unit)
            if not ok then name = "?" end
            -- Order matters: isSecret check BEFORE any nil/truthy comparison.
            if isSecret(name) then
                -- Pass secret strings directly to SetText (per Cell pattern).
                f.nameText:SetText(name)
            else
                if name == nil then name = "?" end
                local maxLen = db.nameMaxLength or 0
                if maxLen > 0 and #name > maxLen then name = name:sub(1, maxLen) end
                f.nameText:SetText(name)
            end
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
    -- Bar value: SetValue accepts secret values. Order all secret-checks
    -- BEFORE any nil/inequality comparison to avoid taint.
    if f.healthBar and not isSecret(max) and max and max > 0 then
        f.healthBar:SetMinMaxValues(0, max)
        if isSecret(cur) then
            pcall(f.healthBar.SetValue, f.healthBar, cur)
        elseif cur ~= nil then
            f.healthBar:SetValue(cur)
        else
            f.healthBar:SetValue(0)
        end
    end

    -- HP text — abbreviated current value only.
    if f.healthText then
        if compact or not db.showHealthText then
            f.healthText:Hide()
        else
            local curStr
            if isSecret(cur) and AbbreviateNumbers then
                pcall(function() curStr = AbbreviateNumbers(cur) end)
            elseif cur ~= nil and AbbreviateNumbers then
                curStr = AbbreviateNumbers(cur)
            elseif cur ~= nil then
                curStr = tostring(cur)
            end

            if isSecret(curStr) then
                f.healthText:SetText(curStr); f.healthText:Show()
            elseif curStr == nil or curStr == "" then
                f.healthText:Hide()
            else
                f.healthText:SetText(curStr); f.healthText:Show()
            end
        end
    end

    -- Power bar (rage / mana / runic / energy / fury / pain — auto by spec)
    if f.powerBar and not compact and db.showPowerBar and (db.powerBarHeight or 0) > 0 then
        local pType
        pcall(function() pType = UnitPowerType(unit) end)
        if isSecret(pType) then pType = nil end

        local pp, ppMax
        pcall(function() pp = UnitPower(unit) end)
        pcall(function() ppMax = UnitPowerMax(unit) end)

        if not isSecret(ppMax) and ppMax and ppMax > 0 then
            f.powerBar:SetMinMaxValues(0, ppMax)
            if isSecret(pp) then
                pcall(f.powerBar.SetValue, f.powerBar, pp)
            elseif pp ~= nil then
                f.powerBar:SetValue(pp)
            else
                f.powerBar:SetValue(0)
            end

            local pr, pg, pb
            if db.powerColorMode == "STATIC" then
                local c = db.powerStaticColor or { r = 0.4, g = 0.4, b = 1 }
                pr, pg, pb = c.r, c.g, c.b
            else
                local pc = POWER_COLORS[pType or -1] or { r = 0.5, g = 0.5, b = 0.5 }
                pr, pg, pb = pc.r, pc.g, pc.b
            end
            f.powerBar:SetStatusBarColor(pr, pg, pb)
            f.powerBar:Show()
        else
            f.powerBar:Hide()
        end
    elseif f.powerBar then
        f.powerBar:Hide()
    end

    -- Power text — abbreviated current value only.
    if f.powerText then
        if compact or not db.showPowerText then
            f.powerText:Hide()
        else
            local pp
            pcall(function() pp = UnitPower(unit) end)

            local ppStr
            if isSecret(pp) and AbbreviateNumbers then
                pcall(function() ppStr = AbbreviateNumbers(pp) end)
            elseif pp ~= nil and AbbreviateNumbers then
                ppStr = AbbreviateNumbers(pp)
            elseif pp ~= nil then
                ppStr = tostring(pp)
            end

            if isSecret(ppStr) then
                f.powerText:SetText(ppStr); f.powerText:Show()
            elseif ppStr == nil or ppStr == "" then
                f.powerText:Hide()
            else
                f.powerText:SetText(ppStr); f.powerText:Show()
            end
        end
    end

    -- Absorb shield overlay
    if f.absorbBar then
        if compact or not db.showAbsorbBar then
            f.absorbBar:Hide()
        elseif isSecret(max) or not max or max <= 0 then
            f.absorbBar:Hide()
        else
            local abs
            pcall(function() abs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) end)
            -- Detect "no absorb" without comparing a secret value.
            local hasAbs
            if isSecret(abs) then hasAbs = true
            elseif abs and abs > 0 then hasAbs = true
            else hasAbs = false end

            if not hasAbs then
                f.absorbBar:Hide()
            else
                f.absorbBar:SetMinMaxValues(0, max)
                pcall(f.absorbBar.SetValue, f.absorbBar, abs or 0)
                local c = db.absorbBarColor or { r = 1, g = 1, b = 1, a = 0.55 }
                f.absorbBar:SetStatusBarColor(c.r, c.g, c.b, c.a or 0.55)
                f.absorbBar:Show()
            end
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
    applyBackgroundFill(f, db, unit, nil)

    if TW.UpdateAuras then TW.UpdateAuras(f) end
end

local function RefreshAll()
    if not TW.TankContainer then return end
    ApplyLayout()
    if TW.ApplyFonts then TW:ApplyFonts() end
    -- Re-evaluate the unit list — visibilityMode / tankDetection / forceInclude*
    -- are read inside collectTankUnits, so a settings change must walk that
    -- path again or stale frames stay visible.
    if TW.RefreshTanks then TW:RefreshTanks() end
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
            -- Re-stamp the modifier-click macros with the new unit token.
            -- Safe out of combat; gracefully no-ops in combat (the OOC
            -- handler below re-runs them via _pendingLayout flush).
            if f.applyClickActions then f.applyClickActions() end
            f:Show()
            UpdateFrame(f)
        elseif not f._testMode then
            f._unit = nil
            f:SetAttribute("unit", nil)
            f:Hide()
        end
    end
    ApplyLayout()
    -- Re-bind the private aura anchors for the new unit set. C_UnitAuras
    -- private auras (Midnight 12.0+) render boss debuffs that don't show
    -- up via GetAuraSlots — without these anchors we miss them.
    if TW.ApplyAllPrivateAuras then TW:ApplyAllPrivateAuras() end
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
        -- Float above tank frames so the player can drag even when a real
        -- unit is anchored to a tank slot (the SecureUnitButton would
        -- otherwise eat clicks). HIGH strata sits above the default MEDIUM
        -- of unit frames.
        m:SetFrameStrata("HIGH")
        m:SetFrameLevel(100)
        local fs = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        fs:SetPoint("CENTER")
        fs:SetText("TankWatch  (RMB: lock)")
        m:SetScript("OnDragStart", function() container:SetMovable(true); container:StartMoving() end)
        m:SetScript("OnDragStop", function()
            container:StopMovingOrSizing()
            snapAndStore(container)
            ApplyLayout()
        end)
        m:SetScript("OnMouseDown", function(self, button)
            if button == "RightButton" then TW:ToggleMover() end
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

-- Test absorb: random target between 0 and 50% of max HP
local function pickTestAbsorbTarget(f)
    -- 30% chance the absorb drops to 0 (representing it expiring), else 5-50% of HP
    if math.random() < 0.3 then
        f._testAbsorbTarget = 0
    else
        f._testAbsorbTarget = math.random(50, 500)
    end
end

-- Test power: behavior depends on type. Rage spikes up + decays; Mana drifts;
-- Energy / Fury / Pain regenerate quickly; Runic power slowly. Each pick picks
-- a new target around realistic values.
local TEST_POWER_TYPES = { 1, 0, 6, 3, 17, 18, 1, 0 }  -- rage, mana, runic, energy, fury, pain
local function pickTestPowerTarget(f)
    local pType = f._testPowerType or 1
    local maxV  = f._testPowerMax or 100
    local cur   = f._testPower or (maxV * 0.5)
    local jitter = (pType == 1 or pType == 17 or pType == 18) and (maxV * 0.5)  -- volatile (rage/fury/pain)
        or (pType == 3) and (maxV * 0.4)  -- energy fluctuates fast
        or (pType == 6) and (maxV * 0.25) -- runic builds slowly
        or (maxV * 0.2)                   -- mana drifts
    local t = cur + math.random(-jitter, jitter)
    if t < 0 then t = math.random(0, maxV * 0.2) end
    if t > maxV then t = maxV - math.random(0, maxV * 0.15) end
    f._testPowerTarget = t
end

-- Apply current settings to a single test frame: respects showName,
-- showHealthText, showAuras, healthColorMode, healthStaticColor.
local function applyTestFrameSettings(f, idx)
    if not f or not f._testMode then return end
    local db  = TW:GetDB()
    local cls = TEST_CLASSES[idx] or "WARRIOR"
    local c   = CLASS_COLORS[cls] or { r = 0.5, g = 0.5, b = 0.5 }

    local compact = db.compactMode and true or false

    -- Raid target marker (one per test frame, cycling 1..8 by index)
    if f.raidTargetIcon then
        if db.showRaidTargetIcon ~= false and SetRaidTargetIconTexCoord then
            local marker = ((idx - 1) % 8) + 1
            local ok = pcall(SetRaidTargetIconTexCoord, f.raidTargetIcon, marker)
            if ok then f.raidTargetIcon:Show() else f.raidTargetIcon:Hide() end
        else
            f.raidTargetIcon:Hide()
        end
    end

    -- Class icon for test mode (uses TEST_CLASSES)
    if f.classIcon then
        if compact and db.showClassIcon then
            local c = CLASS_ICON_COORDS[cls]
            if c then f.classIcon:SetTexCoord(c[1], c[2], c[3], c[4]) end
        end
    end

    if f.nameText then
        if compact or not db.showName then
            f.nameText:Hide()
        else
            f.nameText:SetText(TEST_NAMES[idx] or ("Tank" .. idx))
            f.nameText:SetTextColor(1, 1, 1)
            f.nameText:Show()
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
    applyBackgroundFill(f, db, nil, cls)

    if f.healthText then
        if not compact and db.showHealthText then f.healthText:Show() else f.healthText:Hide() end
    end

    -- Power bar (test): set type-color + range. Live values are animated by the ticker.
    if f.powerBar and not compact and db.showPowerBar and (db.powerBarHeight or 0) > 0 then
        local pType = f._testPowerType or TEST_POWER_TYPES[((idx - 1) % #TEST_POWER_TYPES) + 1]
        f._testPowerType = pType
        f._testPowerMax  = 100
        f.powerBar:SetMinMaxValues(0, 100)
        local pr, pg, pb
        if db.powerColorMode == "STATIC" then
            local sc = db.powerStaticColor or { r = 0.4, g = 0.4, b = 1 }
            pr, pg, pb = sc.r, sc.g, sc.b
        else
            local pc = POWER_COLORS[pType] or { r = 0.5, g = 0.5, b = 0.5 }
            pr, pg, pb = pc.r, pc.g, pc.b
        end
        f.powerBar:SetStatusBarColor(pr, pg, pb)
        f.powerBar:Show()
    elseif f.powerBar then
        f.powerBar:Hide()
    end
    if f.powerText then
        if not compact and db.showPowerText then f.powerText:Show() else f.powerText:Hide() end
    end

    -- Absorb test: set range + color. Live value animated by the ticker below.
    if f.absorbBar then
        if not compact and db.showAbsorbBar then
            f.absorbBar:SetMinMaxValues(0, 1000)
            local cc = db.absorbBarColor or { r = 1, g = 1, b = 1, a = 0.55 }
            f.absorbBar:SetStatusBarColor(cc.r, cc.g, cc.b, cc.a or 0.55)
            -- Start hidden — ticker will Show() once non-zero
            f._testAbsorb       = math.random(0, 400)
            f._testAbsorbTarget = math.random(50, 500)
        else
            f.absorbBar:Hide()
            f._testAbsorb = nil
        end
    end

    if TW.SetTestAuras then TW.SetTestAuras(f, idx) end

    -- Fake raid marker preview in test mode (cycle 1..8 across frames).
    f._showRaidTargetIcon = db.showRaidTargetIcon ~= false
    updateRaidTargetIcon(f)
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
            -- Power test: pick a power type per index so the user sees variety
            local pType = TEST_POWER_TYPES[((i - 1) % #TEST_POWER_TYPES) + 1]
            f._testPowerType   = pType
            f._testPowerMax    = 100
            f._testPower       = math.random(20, 80)
            f._testPowerTarget = f._testPower
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

    -- Turning test mode OFF (count == 0): rebind real tank units. Without
    -- this, every frame stays hidden with _unit = nil — the user sees no
    -- frames at all until the next roster event.
    if count == 0 and TW.RefreshTanks then TW:RefreshTanks() end

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
                    -- HP — exponential ease toward target (rate ~6/s)
                    f._testHP       = f._testHP       or 700
                    f._testHPTarget = f._testHPTarget or f._testHP
                    if pickNew then pickTestTarget(f) end
                    local rateHP = 6 * elapsed
                    if rateHP > 1 then rateHP = 1 end
                    f._testHP = f._testHP + (f._testHPTarget - f._testHP) * rateHP
                    f.healthBar:SetValue(f._testHP)
                    if f.healthText and db.showHealthText then
                        f.healthText:SetText(AbbreviateNumbers and AbbreviateNumbers(math.floor(f._testHP + 0.5)) or tostring(math.floor(f._testHP + 0.5)))
                    end

                    -- Absorb — drift around with occasional drops to 0 (expiry)
                    if f.absorbBar and db.showAbsorbBar then
                        f._testAbsorb       = f._testAbsorb       or 0
                        f._testAbsorbTarget = f._testAbsorbTarget or 0
                        if pickNew then pickTestAbsorbTarget(f) end
                        local rateA = 4 * elapsed
                        if rateA > 1 then rateA = 1 end
                        f._testAbsorb = f._testAbsorb + (f._testAbsorbTarget - f._testAbsorb) * rateA
                        if f._testAbsorb < 1 then
                            f.absorbBar:Hide()
                        else
                            f.absorbBar:SetValue(f._testAbsorb)
                            f.absorbBar:Show()
                        end
                    end

                    -- Power — animate toward target, faster for energy/fury (twitchy)
                    if f.powerBar and db.showPowerBar and (db.powerBarHeight or 0) > 0 then
                        f._testPower       = f._testPower       or 50
                        f._testPowerTarget = f._testPowerTarget or f._testPower
                        if pickNew then pickTestPowerTarget(f) end
                        local pType = f._testPowerType or 1
                        -- Energy / Fury / Pain twitch faster; rage moderate; runic slow
                        local ratePW = elapsed * (
                            (pType == 3 or pType == 17 or pType == 18) and 8
                            or (pType == 1) and 5
                            or (pType == 6) and 2
                            or 3)
                        if ratePW > 1 then ratePW = 1 end
                        f._testPower = f._testPower + (f._testPowerTarget - f._testPower) * ratePW
                        f.powerBar:SetValue(f._testPower)
                        if f.powerText and db.showPowerText then
                            f.powerText:SetText(tostring(math.floor(f._testPower + 0.5)))
                        end
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
ev:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
ev:RegisterEvent("UNIT_POWER_FREQUENT")
ev:RegisterEvent("UNIT_MAXPOWER")
ev:RegisterEvent("UNIT_DISPLAYPOWER")
ev:RegisterEvent("PLAYER_DEAD")
ev:RegisterEvent("PLAYER_UNGHOST")
ev:RegisterEvent("PLAYER_ALIVE")
ev:RegisterEvent("UNIT_FLAGS")
ev:RegisterEvent("RAID_TARGET_UPDATE")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_FOCUS_CHANGED")
ev:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if event == "PLAYER_REGEN_ENABLED" then
        if _pendingLayout then _pendingLayout = false; ApplyLayout() end
        TW:RefreshTanks()
        -- Flush any private-aura anchor registrations that were deferred
        -- because we couldn't call C_UnitAuras.AddPrivateAuraAnchor mid-
        -- combat (Blizzard rejects the API during combat lockdown).
        if TW.FlushPendingPrivateAuras then TW:FlushPendingPrivateAuras() end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED"
        or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Wipe the per-unit aura cache so stale entries from removed
        -- tanks (or unit-token reassignments after a roster shuffle)
        -- don't linger. The cache repopulates on the next UNIT_AURA.
        if TW.WipeAuraCache then TW:WipeAuraCache() end
        TW:RefreshTanks()
    elseif event == "RAID_TARGET_UPDATE" then
        -- RAID_TARGET_UPDATE has no unit arg; refresh every visible frame's marker
        TW._rtRealPrinted = nil -- reset debug so we print on each event
        for i = 1, MAX_TANKS do
            local f = TW.TankFrames[i]
            if f and f._unit then updateRaidTargetIcon(f) end
        end
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
        -- Re-evaluate the target/focus highlight ring on every frame.
        for i = 1, MAX_TANKS do
            local f = TW.TankFrames[i]
            if f and f.refreshHighlight then f:refreshHighlight() end
        end
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_AURA"
        or event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_FLAGS"
        or event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
        -- Feed the aura cache the event payload BEFORE refreshing
        -- frames so the cache has up-to-date data when UpdateAuras
        -- iterates it — but ONLY for units bound to a tank frame.
        -- UNIT_AURA also fires for nameplates / arena / focus units;
        -- in 12.1 those carry fully secret payloads (212x Lua errors
        -- observed on nameplate3) and they polluted the cache with
        -- units we never render.
        local auraFed = false
        for i = 1, MAX_TANKS do
            local f = TW.TankFrames[i]
            if f and f._unit then
                local match = (f._unit == unit)
                if not match and UnitIsUnit then
                    local ok, same = pcall(UnitIsUnit, f._unit, unit)
                    if ok and not isSecret(same) and same == true then match = true end
                end
                if match then
                    if event == "UNIT_AURA" and not auraFed and TW.HandleUnitAura then
                        TW:HandleUnitAura(unit, updateInfo)
                        auraFed = true
                    end
                    UpdateFrame(f)
                end
            end
        end
    elseif event == "PLAYER_DEAD" or event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then
        -- Player-only events have no unit arg; refresh every frame that
        -- resolves to "player" (typically frame[1] in solo mode).
        for i = 1, MAX_TANKS do
            local f = TW.TankFrames[i]
            if f and f._unit then UpdateFrame(f) end
        end
    end
end)
