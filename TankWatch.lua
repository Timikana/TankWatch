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

    -- Container
    anchor = "LEFT", anchorX = 50, anchorY = 0,
    frameWidth = 200, frameHeight = 36, frameSpacing = 4, frameScale = 1.0,
    growDirection = "DOWN",

    -- Bars
    healthTexture = "Blizzard Raid Bar",
    healthBackgroundAlpha = 0.35,
    healthColorMode = "CLASS", -- CLASS | REACTION | STATIC

    -- Name text
    showName = true, nameAnchor = "LEFT", nameX = 4, nameY = 0, nameMaxLength = 14,
    showHealthText = true, healthTextAnchor = "RIGHT", healthTextX = -4, healthTextY = 0,
    healthTextFormat = "PERCENT",

    -- Auras (boss-cast debuffs with stacks emphasis)
    showAuras = true, aurasMaxCount = 5, aurasSize = 28, aurasSpacing = 2,
    aurasAnchor = "RIGHT", aurasX = 6, aurasY = 0, aurasGrowX = "RIGHT",
    aurasOnlyStacks = false, -- if true, only show debuffs with applications > 1

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
    TankWatchDB.minimap = TankWatchDB.minimap or { hide = true, angle = 200 }
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

function TW:ExportProfile(name)
    local root = ensureRoot()
    name = name or TW:GetActiveProfileName()
    local p = root.profiles[name]
    if not p then return nil end
    return "TW1!" .. serialize(p)
end

function TW:ImportProfile(name, str)
    if not str or str == "" then return false, "empty" end
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    if not str:find("^TW1!") then return false, "bad header" end
    local body = str:sub(5)
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
                for _, a in ipairs(f._auras) do
                    setF(a.stacks, size + 2, outline ~= "" and outline or "OUTLINE")
                    setF(a.timer,  size,     outline ~= "" and outline or "OUTLINE")
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
    else
        local L = TW.L
        print("|cff00ff96TankWatch:|r " .. L["commands:"])
        print("  /tw            - " .. L["open options"])
        print("  /tw mover      - " .. L["toggle mover"])
        print("  /tw test N     - " .. L["simulate N tanks (0-8)"])
        print("  /tw reset      - " .. L["reset all settings + reload"])
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
    icon:SetTexture([[Interface\Icons\Spell_Holy_GreaterBlessingofKings]])
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
