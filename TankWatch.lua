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
-- DB ACCESS
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

function TW:GetDB()
    TankWatchDB = TankWatchDB or {}
    seedDefaults(TankWatchDB)
    return TankWatchDB
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
    print(format(TW.L["|cff00ff96TankWatch|r v%s loaded — type |cffffff00/tw|r for options"],
        C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"))
end)
