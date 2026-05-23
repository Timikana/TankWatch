local addonName, TW = ...
local L = TW.L

local h = TW._OptHelpers
local makeSection         = h.makeSection
local makeCheck           = h.makeCheck
local makeDropdown        = h.makeDropdown
local addTooltip          = h.addTooltip
local markAsNew           = h.markAsNew
local _registerInSection  = h.registerInSection
-- Late-bound: defined after the initial _OptHelpers literal in Panel.lua,
-- so they're nil if we cache them at file load. Read on first call.

TW.OptPages = TW.OptPages or {}

function TW.OptPages.buildFilters(page)
    local makeNameList  = h.makeNameList
    local makeSpellList = h.makeSpellList
    local y = -8

    -- ============ TANK DETECTION ============
    makeSection(page, L["Tank detection"], 14, y); y = y - 24

    addTooltip(markAsNew(makeDropdown(page, L["Detection mode"], "tankDetection", {
        { text = L["Group role (auto-set from spec)"], value = "ROLE" },
        { text = L["Only /maintank (raid)"],           value = "MAINTANK" },
        { text = L["Either role or /maintank"],        value = "BOTH" },
    }, 14, y, 260), "v1.x_tankDetection"),
        L["How TankWatch decides who counts as a tank in your group."])
    y = y - 56

    addTooltip(makeCheck(page, L["Always include me if my spec is tank"], "forceIncludeSelf", 14, y),
        L["Add yourself to the tank list when your active spec role is TANK, even if the raid leader didn't /maintank you."])
    y = y - 30

    local nl = makeNameList(page, "forceIncludeNames",
        L["Always include these players (added on top of detected tanks):"],
        14, y, 360, 60)
    y = y - 16 - 60 - 30

    -- ============ DEBUFF FILTERS ============
    y = y - 8
    makeSection(page, L["Debuff filters"], 14, y); y = y - 24

    addTooltip(makeDropdown(page, L["Filter mode"], "auraFilterMode", {
        { text = L["All debuffs (blacklist trims)"], value = "ALL" },
        { text = L["Whitelist only"],                value = "WHITELIST" },
    }, 14, y, 260),
        L["Tous : affiche tous les HARMFUL sauf ceux dans la blacklist. La whitelist force l'affichage. — Whitelist : affiche uniquement les spellIDs whitelistés."])
    y = y - 56

    local note = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 14, y)
    note:SetWidth(680); note:SetJustifyH("LEFT")
    note:SetText(L["Whitelist always shows regardless of mode. Blacklist always hides."])
    y = y - 32

    local listH = 170
    local listW = 240
    local wl = makeSpellList(page, "auraWhitelist", L["Whitelist (always show)"], 14,             y, listW, listH)
    local bl = makeSpellList(page, "auraBlacklist", L["Blacklist (never show)"],  14 + listW + 22, y, listW, listH)

    page._refreshFilters = function() wl.refresh(); bl.refresh(); nl.refresh() end
    page._refreshFilters()
end
