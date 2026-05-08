local addonName, TW = ...

_G[addonName] = TW

TW.MAX_TANKS = 8
TW.TankFrames = {}
TW.TankContainer = nil

-- ============================================================
-- DEFAULTS
-- ============================================================
TW.Defaults = {
    enabled = true,

    -- Visibility scope:
    --   "RAID"   → only show frames when in a raid (recommended for tank-watching)
    --   "GROUP"  → show in raid or 5-man party
    --   "ALWAYS" → also show solo (only useful for self when tank-spec)
    visibilityMode = "RAID",

    -- Container
    anchor = "LEFT", anchorX = 50, anchorY = 0,
    frameWidth = 200, frameHeight = 36, frameSpacing = 4, frameScale = 1.0,
    growDirection = "DOWN",

    -- Bars
    healthTexture = "Blizzard Raid Bar",
    healthBackgroundAlpha = 0.35,
    healthBackgroundColor = { r = 0.1, g = 0.1, b = 0.1 },
    backgroundColorMode   = "STATIC", -- "STATIC" | "CLASS"
    useBackgroundTexture    = false,
    healthBackgroundTexture = "Blizzard Raid Bar", -- LSM name when texture mode is on
    healthColorMode = "CLASS", -- CLASS | REACTION | STATIC
    healthStaticColor = { r = 0.2, g = 0.6, b = 0.2 },

    -- Name text
    showName = true, nameAnchor = "LEFT", nameX = 4, nameY = 0, nameMaxLength = 14,
    showHealthText = true, healthTextAnchor = "RIGHT", healthTextX = 0, healthTextY = 0,
    healthTextFormat = "CURRENT",

    -- Auras (boss-cast debuffs with stacks emphasis)
    showAuras = true, aurasMaxCount = 5, aurasSize = 28, aurasSpacing = 2,
    aurasAnchor = "RIGHT", aurasX = 6, aurasY = 0, aurasGrowX = "RIGHT",
    aurasOnlyStacks = false, -- if true, only show debuffs with applications > 1
    auraFilterMode  = "BOSS", -- "ALL" | "BOSS" | "WHITELIST"
    auraWhitelist   = {},    -- [spellID] = true  → always show (regardless of mode)
    auraBlacklist   = {},    -- [spellID] = true  → never show

    -- Stack count: small, bottom-right corner by default
    auraStackAnchor = "BOTTOMRIGHT",
    auraStackX      = 3,
    auraStackY      = -2,
    auraStackSize   = 0, -- 0 = auto (~0.9x global font size)

    -- Timer: HUGE, centered by default — the prominent live countdown
    auraTimerShow   = true,
    auraTimerAnchor = "CENTER",
    auraTimerX      = 0,
    auraTimerY      = 4,
    auraTimerSize   = 0, -- 0 = auto (~1.6x global font size)

    -- Range fade
    rangeFadeEnabled = true,
    rangeFadeAlpha   = 0.4,

    -- Tank detection mode
    --   "ROLE"     → UnitGroupRolesAssigned == "TANK" (Blizzard auto-assigns this from spec)
    --   "MAINTANK" → only units explicitly /maintank'd by the RL (raid only)
    --   "BOTH"     → union of the two
    tankDetection = "BOTH",

    -- Force-include the player if their spec is tank (off by default — BOTH
    -- detection above usually catches you). Toggle on if your raid leader
    -- doesn't role-check and doesn't /maintank.
    forceIncludeSelf  = false,
    forceIncludeNames = {}, -- [normalizedName] = true → always treat them as a tank

    -- Font
    fontFace = "Friz Quadrata TT", fontSize = 12, fontOutline = "OUTLINE",
}

-- ============================================================
-- DB ACCESS  (profile-based)
--   TankWatchDB = {
--     version     = 2,
--     profiles    = { ["Default"] = {settings...}, ... },
--     profileKeys = { ["Name - Realm"] = "Default", ... },
--   }
-- ============================================================
local function seedDefaults(target)
    for k, v in pairs(TW.Defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                local c = {}
                for kk, vv in pairs(v) do c[kk] = vv end
                target[k] = c
            else
                target[k] = v
            end
        end
    end
end

function TW:GetCharKey()
    local n = UnitName("player") or "?"
    local r = GetRealmName() or "?"
    return n .. " - " .. r
end

local function ensureRoot()
    TankWatchDB = TankWatchDB or {}
    if not TankWatchDB.profiles then
        -- Migration from flat schema (v1) → profiles (v2)
        local migrated = {}
        for k, _ in pairs(TW.Defaults) do
            if TankWatchDB[k] ~= nil then
                migrated[k] = TankWatchDB[k]
                TankWatchDB[k] = nil
            end
        end
        TankWatchDB.profiles    = { ["Default"] = migrated }
        TankWatchDB.profileKeys = {}
        TankWatchDB.version     = 2
    end
    if not TankWatchDB.profiles["Default"] then
        TankWatchDB.profiles["Default"] = {}
    end
    TankWatchDB.profileKeys = TankWatchDB.profileKeys or {}
    TankWatchDB.minimap = TankWatchDB.minimap or { hide = false, angle = 200 }
    return TankWatchDB
end

function TW:GetGlobalDB() return ensureRoot() end

function TW:GetActiveProfileName()
    local root = ensureRoot()
    local key = TW:GetCharKey()
    local name = root.profileKeys[key]
    if name and root.profiles[name] then return name end
    root.profileKeys[key] = "Default"
    return "Default"
end

function TW:GetDB()
    local root = ensureRoot()
    local p = root.profiles[TW:GetActiveProfileName()]
    seedDefaults(p)
    return p
end

function TW:ListProfiles()
    local root = ensureRoot()
    local list = {}
    for name in pairs(root.profiles) do list[#list + 1] = name end
    table.sort(list, function(a, b)
        if a == "Default" then return true end
        if b == "Default" then return false end
        return a:lower() < b:lower()
    end)
    return list
end

function TW:SetActiveProfile(name)
    local root = ensureRoot()
    if not root.profiles[name] then return false end
    root.profileKeys[TW:GetCharKey()] = name
    seedDefaults(root.profiles[name])
    if TW.RefreshAll  then TW:RefreshAll()  end
    if TW.ApplyFonts  then TW:ApplyFonts()  end
    if TW.ApplyLayout then TW:ApplyLayout() end
    return true
end

function TW:CreateProfile(name, copyFrom)
    name = name and name:gsub("^%s+", ""):gsub("%s+$", "")
    if not name or name == "" then return false, "empty name" end
    local root = ensureRoot()
    if root.profiles[name] then return false, "exists" end
    local src = copyFrom and root.profiles[copyFrom] or nil
    local p = {}
    if src then for k, v in pairs(src) do p[k] = v end end
    seedDefaults(p)
    root.profiles[name] = p
    return true
end

function TW:DeleteProfile(name)
    if name == "Default" then return false, "cannot delete Default" end
    local root = ensureRoot()
    if not root.profiles[name] then return false, "not found" end
    root.profiles[name] = nil
    -- Any char pointing to it falls back to Default
    for k, v in pairs(root.profileKeys) do
        if v == name then root.profileKeys[k] = "Default" end
    end
    return true
end

function TW:ResetCurrentProfile()
    local root = ensureRoot()
    local name = TW:GetActiveProfileName()
    root.profiles[name] = {}
    seedDefaults(root.profiles[name])
end

-- ============================================================
-- PROFILE SERIALIZATION (export / import)
-- Format: "TW2!" .. base64(lua_table_literal)
-- Legacy "TW1!" .. lua_table_literal is still accepted on import.
-- ============================================================
local function serialize(v)
    local tp = type(v)
    if tp == "string"  then return string.format("%q", v) end
    if tp == "number"  then return tostring(v) end
    if tp == "boolean" then return tostring(v) end
    if tp == "table"   then
        local parts = {}
        for k, val in pairs(v) do
            local key
            if type(k) == "string"     then key = "[" .. string.format("%q", k) .. "]"
            elseif type(k) == "number" then key = "[" .. k .. "]"
            else key = nil end
            local s = serialize(val)
            if key and s then parts[#parts + 1] = key .. "=" .. s end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
end

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64lookup = {}
for i = 1, #b64chars do b64lookup[b64chars:sub(i, i)] = i - 1 end

local function b64encode(data)
    if not data or data == "" then return "" end
    local out, len = {}, #data
    for i = 1, len, 3 do
        local b1 = data:byte(i)
        local b2 = data:byte(i + 1)
        local b3 = data:byte(i + 2)
        local n  = b1 * 0x10000 + (b2 or 0) * 0x100 + (b3 or 0)
        local c1 = math.floor(n / 0x40000) % 0x40
        local c2 = math.floor(n / 0x1000)  % 0x40
        local c3 = math.floor(n / 0x40)    % 0x40
        local c4 = n % 0x40
        out[#out + 1] = b64chars:sub(c1 + 1, c1 + 1)
        out[#out + 1] = b64chars:sub(c2 + 1, c2 + 1)
        out[#out + 1] = b2 and b64chars:sub(c3 + 1, c3 + 1) or "="
        out[#out + 1] = b3 and b64chars:sub(c4 + 1, c4 + 1) or "="
    end
    return table.concat(out)
end

local function b64decode(data)
    if not data or data == "" then return "" end
    data = data:gsub("[^%w%+%/%=]", "")
    local out, len = {}, #data
    for i = 1, len, 4 do
        local c1c = data:sub(i,     i    )
        local c2c = data:sub(i + 1, i + 1)
        local c3c = data:sub(i + 2, i + 2)
        local c4c = data:sub(i + 3, i + 3)
        local c1 = b64lookup[c1c] or 0
        local c2 = b64lookup[c2c] or 0
        local c3 = b64lookup[c3c] or 0
        local c4 = b64lookup[c4c] or 0
        local n  = c1 * 0x40000 + c2 * 0x1000 + c3 * 0x40 + c4
        out[#out + 1] = string.char(math.floor(n / 0x10000) % 0x100)
        if c3c ~= "=" then out[#out + 1] = string.char(math.floor(n / 0x100) % 0x100) end
        if c4c ~= "=" then out[#out + 1] = string.char(n % 0x100) end
    end
    return table.concat(out)
end

function TW:ExportProfile(name)
    local root = ensureRoot()
    name = name or TW:GetActiveProfileName()
    local p = root.profiles[name]
    if not p then return nil end
    return "TW2!" .. b64encode(serialize(p))
end

function TW:ImportProfile(name, str)
    if not str or str == "" then return false, "empty" end
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    local body
    if str:find("^TW2!") then
        body = b64decode(str:sub(5))
    elseif str:find("^TW1!") then
        body = str:sub(5)
    else
        return false, "bad header"
    end
    if not body or body == "" then return false, "decode failed" end
    local f, err = (loadstring or load)("return " .. body, "TW-import", "t", {})
    if not f then return false, "parse: " .. tostring(err) end
    if setfenv then setfenv(f, {}) end
    local ok, result = pcall(f)
    if not ok or type(result) ~= "table" then return false, "decode failed" end
    name = name and name:gsub("^%s+", ""):gsub("%s+$", "")
    if not name or name == "" then return false, "empty name" end
    local root = ensureRoot()
    seedDefaults(result)
    root.profiles[name] = result
    return true
end

-- ============================================================
-- LSM REGISTRATION (modern Blizzard cast bar texture)
-- ============================================================
do
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        LSM:Register("statusbar", "Blizzard Modern", [[Interface\TargetingFrame\UI-TargetingFrame-BarFill]])
    end
end

-- ============================================================
-- TEXTURE / FONT RESOLUTION
-- ============================================================
function TW:ResolveTexture(name)
    if not name or name == "" then return "Interface\\TargetingFrame\\UI-StatusBar" end
    if name:find("\\") or name:find("/") then return name end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local p = LSM:Fetch("statusbar", name)
        if p then return p end
    end
    return "Interface\\TargetingFrame\\UI-StatusBar"
end

function TW:ResolveFont(name)
    local fallback = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    if not name or name == "" then return fallback end
    if name:find("\\") or name:find("/") then return name end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local p = LSM:Fetch("font", name)
        if p then return p end
    end
    return fallback
end

function TW:ApplyFonts()
    if not TW.TankFrames then return end
    local db = TW:GetDB()
    local file = TW:ResolveFont(db.fontFace)
    local size = db.fontSize or 12
    local outline = db.fontOutline or "NONE"
    if outline == "NONE" then outline = "" end
    local function setF(fs, sz, ol)
        if fs then pcall(fs.SetFont, fs, file, sz, ol) end
    end
    for i = 1, TW.MAX_TANKS do
        local f = TW.TankFrames[i]
        if f then
            setF(f.nameText,   size, outline)
            setF(f.healthText, size, outline)
            if f._auras then
                local strongOutline = (outline == "THICKOUTLINE") and "THICKOUTLINE" or "OUTLINE"
                -- Timer is the prominent display (~1.6x), stack count secondary (~0.9x)
                local timerSz = (db.auraTimerSize and db.auraTimerSize > 0)
                    and db.auraTimerSize or math.floor(size * 1.6 + 0.5)
                local stackSz = (db.auraStackSize and db.auraStackSize > 0)
                    and db.auraStackSize or math.max(9, math.floor(size * 0.9 + 0.5))
                for _, a in ipairs(f._auras) do
                    setF(a.stacks, stackSz, strongOutline)
                    setF(a.timer,  timerSz, strongOutline)
                end
            end
        end
    end
end

-- ============================================================
-- LOCALIZATION
-- ============================================================
TW.L = setmetatable({}, { __index = function(_, k) return k end })

-- ============================================================
-- SLASH
-- ============================================================
SLASH_TANKWATCH1 = "/tw"
SLASH_TANKWATCH2 = "/tankwatch"
SlashCmdList["TANKWATCH"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" or msg == "config" or msg == "options" then
        if TW.ToggleOptions then TW:ToggleOptions() end
        return
    end
    local cmd, arg = msg:match("^(%S+)%s*(.*)$")
    if cmd == "test" then
        if TW.SetTestMode then TW:SetTestMode(tonumber(arg) or 3) end
    elseif cmd == "mover" then
        if TW.ToggleMover then TW:ToggleMover() end
    elseif cmd == "reset" then
        TankWatchDB = nil
        ReloadUI()
    elseif cmd == "debug" or cmd == "diag" then
        if TW.PrintRosterDebug then TW:PrintRosterDebug() end
    elseif cmd == "auradebug" or cmd == "auras" then
        if TW.PrintAuraDebug then TW:PrintAuraDebug() end
    else
        local L = TW.L
        print("|cff00ff96TankWatch:|r " .. L["commands:"])
        print("  /tw            - " .. L["open options"])
        print("  /tw mover      - " .. L["toggle mover"])
        print("  /tw test N     - " .. L["simulate N tanks (0-8)"])
        print("  /tw reset      - " .. L["reset all settings + reload"])
        print("  /tw debug      - " .. L["print roster role/maintank info"])
        print("  /tw auradebug  - " .. L["print every HARMFUL aura on each tank unit"])
    end
end

-- ============================================================
-- MINIMAP BUTTON (manual, no LibDBIcon dependency)
-- ============================================================
local minimapBtn

local function placeMinimapButton()
    if not minimapBtn then return end
    local mm = TankWatchDB and TankWatchDB.minimap or { angle = 200 }
    local angle = math.rad(mm.angle or 200)
    local radius = 80
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function TW:UpdateMinimapButton()
    if not minimapBtn then return end
    local mm = TankWatchDB and TankWatchDB.minimap
    if mm and mm.hide then minimapBtn:Hide() else minimapBtn:Show() end
    placeMinimapButton()
end

function TW:CreateMinimapButton()
    if minimapBtn or not Minimap then return end
    local b = CreateFrame("Button", "TankWatchMinimapButton", Minimap)
    b:SetSize(32, 32)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetMovable(true)

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20); icon:SetPoint("CENTER", b, "CENTER", 0, 1)
    icon:SetTexture([[Interface\AddOns\TankWatch\Media\icon]])
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54); border:SetPoint("TOPLEFT")
    border:SetTexture([[Interface\Minimap\MiniMap-TrackingBorder]])

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if TW.ToggleMover then TW:ToggleMover() end
        else
            if TW.ToggleOptions then TW:ToggleOptions() end
        end
    end)

    b:SetScript("OnDragStart", function(self) self.isDragging = true end)
    b:SetScript("OnDragStop",  function(self) self.isDragging = false end)
    b:SetScript("OnUpdate", function(self)
        if not self.isDragging then return end
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        local angle = math.deg(math.atan2(py - my, px - mx))
        if angle < 0 then angle = angle + 360 end
        TankWatchDB.minimap = TankWatchDB.minimap or {}
        TankWatchDB.minimap.angle = angle
        placeMinimapButton()
    end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff00ff96TankWatch|r")
        GameTooltip:AddLine(TW.L["Left-click: options"],   1, 1, 1)
        GameTooltip:AddLine(TW.L["Right-click: mover"],    1, 1, 1)
        GameTooltip:AddLine(TW.L["Drag: reposition"],      0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    minimapBtn = b
    TW:UpdateMinimapButton()
end

-- ============================================================
-- INIT
-- ============================================================
local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function()
    TW:GetDB()
    if TW.EnsureCreated then TW:EnsureCreated() end
    if TW.ApplyFonts then TW:ApplyFonts() end
    if TW.RefreshTanks then TW:RefreshTanks() end
    if TW.RegisterBlizzardSettings then TW:RegisterBlizzardSettings() end
    if TW.CreateMinimapButton then TW:CreateMinimapButton() end
    print(format(TW.L["|cff00ff96TankWatch|r v%s loaded — type |cffffff00/tw|r for options"],
        C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"))
end)
