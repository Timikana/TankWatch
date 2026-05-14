local addonName, TW = ...
local L = TW.L

local h = TW._OptHelpers
local makeSection      = h.makeSection
local makeSlider       = h.makeSlider
local makeCheck        = h.makeCheck
local makeDropdown     = h.makeDropdown
local addTooltip       = h.addTooltip
local markAsNew        = h.markAsNew
local ANCHOR9          = h.ANCHOR9
local _registerInSection = h.registerInSection

TW.OptPages = TW.OptPages or {}

function TW.OptPages.buildRaid(page)
    local y = -8

    makeSection(page, L["Raid Target Icon"], 14, y); y = y - 24

    local note = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 14, y)
    note:SetWidth(680); note:SetJustifyH("LEFT")
    note:SetText(L["Position the raid target icon (star, circle, diamond, triangle, moon, square, cross, skull) on each tank frame."])
    _registerInSection(note)
    y = y - 30

    addTooltip(makeCheck(page, L["Show Raid Target Icon"], "showRaidTargetIcon", 14, y),
        L["Display the raid target icon (if any) over each tank frame."])
    y = y - 30
    addTooltip(makeDropdown(page, L["Anchor"], "raidTargetIconAnchor", ANCHOR9(), 14, y),
        L["Anchor point of the raid icon on the frame."])
    y = y - 56
    addTooltip(makeSlider(page, L["Offset X"], "raidTargetIconX", -100, 100, 1, 14, y),
        L["Horizontal offset of the raid icon."])
    addTooltip(makeSlider(page, L["Offset Y"], "raidTargetIconY", -100, 100, 1, 260, y),
        L["Vertical offset of the raid icon."])
    y = y - 56
    addTooltip(makeSlider(page, L["Size"], "raidTargetIconSize", 8, 64, 1, 14, y),
        L["Size of the raid icon in pixels."])
    addTooltip(makeSlider(page, L["Alpha"], "raidTargetIconAlpha", 0.1, 1, 0.05, 260, y),
        L["Opacity of the raid icon."])
end
