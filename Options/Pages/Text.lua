local addonName, TW = ...
local L = TW.L

local h = TW._OptHelpers
local makeSection      = h.makeSection
local makeSlider       = h.makeSlider
local makeCheck        = h.makeCheck
local makeDropdown     = h.makeDropdown
local makeMediaDropdown= h.makeMediaDropdown
local addTooltip       = h.addTooltip
local markAsNew        = h.markAsNew
local ANCHOR9          = h.ANCHOR9

TW.OptPages = TW.OptPages or {}

function TW.OptPages.buildText(page)
    local y = -8

    -- ============ NAME ============
    makeSection(page, L["Name"], 14, y); y = y - 24
    addTooltip(makeCheck(page, L["Show Name"], "showName", 14, y),
        L["Show the tank's name on the frame."])
    addTooltip(makeDropdown(page, L["Name Position"], "nameAnchor", ANCHOR9(), 184, y),
        L["Anchor point where the name is attached on the frame."])
    y = y - 56

    addTooltip(makeSlider(page, L["Name Offset X"], "nameX", -80, 80, 1, 14, y),
        L["Horizontal offset of the name from its anchor."])
    addTooltip(makeSlider(page, L["Name Offset Y"], "nameY", -80, 80, 1, 260, y),
        L["Vertical offset of the name from its anchor."])
    y = y - 56
    addTooltip(makeSlider(page, L["Name max length (0=off)"], "nameMaxLength", 0, 30, 1, 14, y, 250),
        L["Trim the name after this many characters. 0 disables trimming."])

    -- ============ HEALTH TEXT ============
    y = y - 60
    makeSection(page, L["Health Text"], 14, y); y = y - 24
    addTooltip(makeCheck(page, L["Show Health Text"], "showHealthText", 14, y),
        L["Display HP value as text on the health bar."])
    addTooltip(makeDropdown(page, L["HP text position"], "healthTextAnchor", ANCHOR9(), 184, y),
        L["Anchor point of the HP text on the bar."])
    y = y - 56
    addTooltip(makeSlider(page, L["HP text Offset X"], "healthTextX", -80, 80, 1, 14, y),
        L["Horizontal offset of the HP text."])
    addTooltip(makeSlider(page, L["HP text Offset Y"], "healthTextY", -80, 80, 1, 260, y),
        L["Vertical offset of the HP text."])

    -- ============ POWER TEXT ============
    y = y - 60
    makeSection(page, L["Power Text"], 14, y); y = y - 24
    addTooltip(markAsNew(makeCheck(page, L["Show Power Text"], "showPowerText", 14, y), "v1.3_powerText"),
        L["Display the power value (rage / mana / etc.) as text."])
    addTooltip(markAsNew(makeDropdown(page, L["Power text position"], "powerTextAnchor", ANCHOR9(), 280, y), "v1.3_powerTextAnchor"),
        L["Anchor point of the power text on its bar."])
    y = y - 56
    addTooltip(markAsNew(makeSlider(page, L["Power text Offset X"], "powerTextX", -80, 80, 1, 14, y), "v1.3_powerTextX"),
        L["Horizontal offset of the power text."])
    addTooltip(markAsNew(makeSlider(page, L["Power text Offset Y"], "powerTextY", -80, 80, 1, 260, y), "v1.3_powerTextY"),
        L["Vertical offset of the power text."])

    -- ============ FONT ============
    y = y - 60
    makeSection(page, L["Font (applies to all text)"], 14, y); y = y - 24
    addTooltip(makeMediaDropdown(page, L["Font"], "fontFace", "font", 14, y, 180),
        L["Font used for every text on the tank frames."])
    y = y - 56
    addTooltip(makeSlider(page, L["Font Size"], "fontSize", 8, 24, 1, 14, y),
        L["Base font size in points."])
    addTooltip(makeDropdown(page, L["Outline"], "fontOutline", {
        { text = L["None"],          value = "NONE" },
        { text = L["Outline"],       value = "OUTLINE" },
        { text = L["Thick Outline"], value = "THICKOUTLINE" },
    }, 260, y), L["Black outline drawn around text for readability."])
end
