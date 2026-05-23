local addonName, TW = ...
local L = TW.L

-- Pull helpers exposed by Options/Panel.lua into file-local upvalues so the
-- body below stays identical to the pre-split version.
local h = TW._OptHelpers
local makeSection      = h.makeSection
local makeSlider       = h.makeSlider
local makeCheck        = h.makeCheck
local makeDropdown     = h.makeDropdown
local makeMediaDropdown= h.makeMediaDropdown
local makeColorPicker  = h.makeColorPicker
local addTooltip       = h.addTooltip
local markAsNew        = h.markAsNew

TW.OptPages = TW.OptPages or {}

function TW.OptPages.buildBars(page)
    local y = -8

    -- ============ HEALTH BAR (texture + color, merged) ============
    makeSection(page, L["Health bar"], 14, y); y = y - 24
    addTooltip(makeMediaDropdown(page, L["Health Texture"], "healthTexture", "statusbar", 14, y, 180),
        L["Status bar texture used for the tank health bar."])
    y = y - 56
    addTooltip(makeDropdown(page, L["Color mode"], "healthColorMode", {
        { text = L["Class color"],      value = "CLASS" },
        { text = L["Reaction (green)"], value = "REACTION" },
        { text = L["Custom static"],    value = "STATIC" },
    }, 14, y, 180),
        L["How the health bar is colored: by class, fixed green, or one custom color."])
    addTooltip(makeColorPicker(page, L["Static color"], "healthStaticColor", 280, y),
        L["Fixed color used when the mode above is set to 'Custom static'."])

    -- ============ BACKGROUND ============
    y = y - 60
    makeSection(page, L["Background"], 14, y); y = y - 24
    addTooltip(markAsNew(makeDropdown(page, L["Background color mode"], "backgroundColorMode", {
        { text = L["Custom static"], value = "STATIC" },
        { text = L["Class color"],   value = "CLASS"  },
    }, 14, y, 180), "v1.0.4_bgColorMode"),
        L["Color used behind the bar fill: a static color or the tank's class color."])
    addTooltip(markAsNew(makeColorPicker(page, L["Background color"], "healthBackgroundColor", 280, y), "v1.0.4_bgColor"),
        L["Custom color used for the health bar background."])
    y = y - 56

    addTooltip(markAsNew(makeCheck(page, L["Use textured background"], "useBackgroundTexture", 14, y), "v1.0.4_bgTexture"),
        L["Use a status-bar texture for the background (otherwise: flat color)."])
    addTooltip(makeSlider(page, L["HP background alpha"], "healthBackgroundAlpha", 0, 1, 0.05, 260, y),
        L["Opacity of the empty (un-filled) part of the health bar."])
    y = y - 56

    addTooltip(markAsNew(makeMediaDropdown(page, L["Background texture"], "healthBackgroundTexture", "statusbar", 14, y, 180), "v1.0.4_bgTextureDD"),
        L["Texture used for the health bar background when the option above is enabled."])

    -- ============ ABSORB SHIELD ============
    y = y - 60
    makeSection(page, L["Absorb shield"], 14, y); y = y - 24
    addTooltip(markAsNew(makeCheck(page, L["Show absorb shield"], "showAbsorbBar", 14, y), "v1.2_absorbBar"),
        L["Overlay a translucent shield bar showing the tank's current absorb amount."])
    addTooltip(markAsNew(makeColorPicker(page, L["Absorb color"], "absorbBarColor", 280, y), "v1.2_absorbBarColor"),
        L["Color and alpha of the absorb shield overlay."])
    y = y - 56
    addTooltip(markAsNew(makeMediaDropdown(page, L["Absorb texture"], "absorbBarTexture", "statusbar", 14, y, 180), "v1.2_absorbBarTexture"),
        L["Status bar texture used for the absorb shield overlay."])
    y = y - 56
    addTooltip(markAsNew(makeDropdown(page, L["Absorb side"], "absorbBarSide", {
        { text = L["Right"], value = "RIGHT" },
        { text = L["Left"],  value = "LEFT" },
    }, 14, y, 160), "v1.2_absorbBarSide"),
        L["Which side of the bar the shield grows from."])

    -- ============ POWER BAR ============
    y = y - 60
    makeSection(page, L["Power bar"], 14, y); y = y - 24
    addTooltip(markAsNew(makeCheck(page, L["Show power bar"], "showPowerBar", 14, y), "v1.3_powerBar"),
        L["Display a thin power bar (rage / mana / runic power / etc.) below the health bar."])
    addTooltip(markAsNew(makeSlider(page, L["Power bar height"], "powerBarHeight", 0, 20, 1, 184, y), "v1.3_powerBarHeight"),
        L["Height in pixels of the power bar. 0 hides the bar entirely."])
    y = y - 56
    addTooltip(markAsNew(makeMediaDropdown(page, L["Power texture"], "powerBarTexture", "statusbar", 14, y, 180), "v1.3_powerBarTexture"),
        L["Status bar texture used for the power bar."])
    y = y - 56
    addTooltip(markAsNew(makeDropdown(page, L["Power color mode"], "powerColorMode", {
        { text = L["By power type"], value = "TYPE" },
        { text = L["Custom static"], value = "STATIC" },
    }, 14, y, 200), "v1.3_powerColorMode"),
        L["How the power bar is colored: automatic by power type (rage = red, mana = blue, etc.) or a fixed custom color."])
    addTooltip(markAsNew(makeColorPicker(page, L["Power static color"], "powerStaticColor", 320, y), "v1.3_powerStaticColor"),
        L["Fixed color used when the mode above is set to 'Custom static'."])

    -- ============ HIGHLIGHT (target / focus / hover) ============
    y = y - 60
    makeSection(page, L["Highlight (target / focus / hover)"], 14, y); y = y - 24
    addTooltip(markAsNew(makeCheck(page, L["Show selection border"], "showHighlight", 14, y), "v1.4.10_highlight"),
        L["Outline the tank frame with a colored border: gold when targeted, cyan when focused, white on mouseover."])
    addTooltip(makeSlider(page, L["Border thickness"], "highlightThickness", 1, 6, 1, 260, y),
        L["Thickness of the highlight border in pixels."])
    y = y - 56
    addTooltip(makeColorPicker(page, L["Target color"], "highlightTargetColor", 14, y),
        L["Border color when this tank is your current target."])
    addTooltip(makeColorPicker(page, L["Focus color"], "highlightFocusColor", 160, y),
        L["Border color when this tank is your focus."])
    addTooltip(makeColorPicker(page, L["Hover color"], "highlightHoverColor", 306, y),
        L["Border color when you mouseover this tank's frame."])
end
