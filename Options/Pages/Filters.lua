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

    -- Share buttons: export the current whitelist/blacklist as a
    -- comma-separated string for sharing on Discord/etc., or import
    -- a pasted string (additive: merges into the existing list).
    -- Positioned BELOW the makeSpellList's own "Spell ID + Ajouter"
    -- row (which sits at y - 18 - h - 4 — i.e. y - h - 22 — with a
    -- ~22px-high row). Buttons go at y - h - 50 to leave a 6px gap.
    local function makeShareButtons(which, xBase, refreshFn)
        local btnExport = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        btnExport:SetSize(70, 22)
        btnExport:SetPoint("TOPLEFT", xBase, y - listH - 50)
        btnExport:SetText(L["Export"])
        addTooltip(btnExport, L["Copy this list as a comma-separated string of spellIDs to share on Discord."])
        btnExport:SetScript("OnClick", function()
            local str = TW:ExportAuraList(which)
            if str == "" then
                print("|cff00ff96TankWatch:|r " .. L["List is empty."])
                return
            end
            local askName = TW._OptHelpers.askName
            askName(L["Copy this list (Ctrl+A → Ctrl+C):"], function() end)
            local p = StaticPopup_Visible("TANKWATCH_PROFILE_NAME")
            if p then
                local d = _G[p]
                if d and d.EditBox then
                    d.EditBox:SetText(str)
                    d.EditBox:HighlightText()
                    d.EditBox:SetFocus()
                end
            end
        end)
        _registerInSection(btnExport)

        local btnImport = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        btnImport:SetSize(70, 22)
        btnImport:SetPoint("LEFT", btnExport, "RIGHT", 6, 0)
        btnImport:SetText(L["Import"])
        addTooltip(btnImport, L["Paste a comma-separated list of spellIDs to add to this list (existing entries are kept)."])
        btnImport:SetScript("OnClick", function()
            local askName = TW._OptHelpers.askName
            askName(L["Paste comma-separated spellIDs:"], function(str)
                local added = TW:ImportAuraList(which, str, false)
                print("|cff00ff96TankWatch:|r " ..
                    string.format(L["Added %d spellIDs."] or "Added %d spellIDs.", added or 0))
                if refreshFn then refreshFn() end
            end)
        end)
        _registerInSection(btnImport)
    end

    makeShareButtons("auraWhitelist", 14,             function() wl.refresh() end)
    makeShareButtons("auraBlacklist", 14 + listW + 22, function() bl.refresh() end)

    page._refreshFilters = function() wl.refresh(); bl.refresh(); nl.refresh() end
    page._refreshFilters()
end
