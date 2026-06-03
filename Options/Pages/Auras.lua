local addonName, TW = ...
local L = TW.L

local h = TW._OptHelpers
local makeSection         = h.makeSection
local makeSlider          = h.makeSlider
local makeCheck           = h.makeCheck
local makeDropdown        = h.makeDropdown
local addTooltip          = h.addTooltip
local markAsNew           = h.markAsNew
local ANCHOR9             = h.ANCHOR9
local _registerInSection  = h.registerInSection

TW.OptPages = TW.OptPages or {}

function TW.OptPages.buildAuras(page)
    local y = -8

    -- ============ RESET ============
    local btnReset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    btnReset:SetSize(180, 22)
    btnReset:SetPoint("TOPRIGHT", page, "TOPRIGHT", -32, y)
    btnReset:SetText(L["Reset aura settings"])
    btnReset:SetScript("OnClick", function()
        if TW.ResetAuraSettings then TW:ResetAuraSettings() end
        if page.refreshAll then page.refreshAll() end
        if TW._OptPanel and TW._OptPanel.refreshAll then TW._OptPanel.refreshAll() end
    end)
    addTooltip(btnReset, L["Reset only the aura-related settings (size, position, filter, blacklist seed, private auras, etc.) back to defaults. Other settings stay untouched."])
    _registerInSection(btnReset)

    -- ============ DISPLAY ============
    makeSection(page, L["Display"], 14, y); y = y - 24
    addTooltip(makeCheck(page, L["Show Auras"], "showAuras", 14, y),
        L["Show the tank's boss-cast debuffs as icons on the frame."])
    addTooltip(makeCheck(page, L["Only debuffs with stacks"], "aurasOnlyStacks", 184, y),
        L["Hide debuffs that don't have a stack count (applications == 1)."])
    y = y - 30
    addTooltip(markAsNew(makeCheck(page, L["Show spellID in tooltip"], "showSpellIDInTooltip", 14, y), "v1.4.10_spellID"),
        L["Append the spellID line at the bottom of the debuff tooltip. Useful to identify a debuff and add it to the whitelist/blacklist in the Filters tab."])
    y = y - 30

    local note = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 14, y)
    note:SetWidth(680); note:SetJustifyH("LEFT")
    note:SetText(L["By default only boss-cast HARMFUL auras show. Use the Filters tab to whitelist M+ debuffs or blacklist noise."])
    _registerInSection(note)
    y = y - 32

    -- ============ ICONS (size + layout merged) ============
    makeSection(page, L["Icons"], 14, y); y = y - 24
    addTooltip(makeSlider(page, L["Max Count"], "aurasMaxCount", 1, 10, 1, 14, y),
        L["Maximum number of debuff icons shown per tank frame."])
    addTooltip(makeSlider(page, L["Size"], "aurasSize", 16, 64, 1, 260, y),
        L["Size of each debuff icon in pixels."])
    y = y - 56
    addTooltip(makeSlider(page, L["Spacing"], "aurasSpacing", 0, 12, 1, 14, y),
        L["Gap between debuff icons in pixels."])
    y = y - 56
    addTooltip(makeDropdown(page, L["Anchor"], "aurasAnchor", ANCHOR9(), 14, y),
        L["Where the debuff row attaches on the tank frame."])
    addTooltip(makeDropdown(page, L["Grow X"], "aurasGrowX", {
        { text = L["Left"],  value = "LEFT" },
        { text = L["Right"], value = "RIGHT" },
    }, 260, y), L["Direction icons stack horizontally from the anchor."])
    y = y - 56
    addTooltip(makeSlider(page, L["Offset X"], "aurasX", -200, 200, 1, 14, y),
        L["Horizontal offset of the debuff row."])
    addTooltip(makeSlider(page, L["Offset Y"], "aurasY", -200, 200, 1, 260, y),
        L["Vertical offset of the debuff row."])

    -- ============ STACK COUNT ============
    y = y - 60
    makeSection(page, L["Stack count"], 14, y); y = y - 24
    addTooltip(markAsNew(makeDropdown(page, L["Stack anchor"], "auraStackAnchor", ANCHOR9(), 14, y), "v1.x_stackPos"),
        L["Anchor point of the stack-count text on each icon."])
    addTooltip(makeSlider(page, L["Stack size (0 = auto)"], "auraStackSize", 0, 32, 1, 260, y, 200),
        L["Font size for the stack number. 0 auto-scales with icon size."])
    y = y - 56
    addTooltip(makeSlider(page, L["Stack offset X"], "auraStackX", -30, 30, 1, 14, y),
        L["Horizontal offset of the stack-count text from its anchor."])
    addTooltip(makeSlider(page, L["Stack offset Y"], "auraStackY", -30, 30, 1, 260, y),
        L["Vertical offset of the stack-count text from its anchor."])

    -- ============ TIMER ============
    y = y - 60
    makeSection(page, L["Timer"], 14, y); y = y - 24
    addTooltip(markAsNew(makeCheck(page, L["Show timer"], "auraTimerShow", 14, y), "v1.x_timerPos"),
        L["Show remaining duration on each debuff icon."])
    addTooltip(makeDropdown(page, L["Timer anchor"], "auraTimerAnchor", ANCHOR9(), 184, y),
        L["Anchor point of the timer text on each icon."])
    y = y - 56
    addTooltip(makeSlider(page, L["Timer size (0 = auto)"], "auraTimerSize", 0, 24, 1, 14, y, 200),
        L["Font size for the timer text. 0 auto-scales with icon size."])
    y = y - 56
    addTooltip(makeSlider(page, L["Timer offset X"], "auraTimerX", -30, 30, 1, 14, y),
        L["Horizontal offset of the timer text from its anchor."])
    addTooltip(makeSlider(page, L["Timer offset Y"], "auraTimerY", -30, 30, 1, 260, y),
        L["Vertical offset of the timer text from its anchor."])

    -- ============ PRIVATE AURAS (merged into the row) ============
    -- Private auras share ALL geometry with the regular debuff row above
    -- (size, spacing, anchor, growX, offsets). Only the count + on/off
    -- toggle remain as private-specific knobs — Blizzard caps the number
    -- of private aura slots per unit so we expose it.
    y = y - 60
    makeSection(page, L["Auras privées (rendues par le boss)"], 14, y); y = y - 24

    local paNote = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    paNote:SetPoint("TOPLEFT", 14, y)
    paNote:SetWidth(680); paNote:SetJustifyH("LEFT")
    paNote:SetText(L["Les private auras s'intègrent à la suite de la rangée principale ci-dessus (même taille, espacement, ancrage). Blizzard contrôle le rendu (tooltip, spellID, police custom ne s'appliquent pas)."])
    _registerInSection(paNote)
    y = y - 40

    addTooltip(makeCheck(page, L["Show private auras"], "showPrivateAuras", 14, y),
        L["Register private aura anchor slots on each tank frame. Disable if you only want the regular Lua-scanned debuffs."])
    y = y - 30

    addTooltip(makeSlider(page, L["Count"], "privateAuraCount", 1, 8, 1, 14, y),
        L["How many private aura anchor slots to register per tank. Blizzard fills them in order (slot 1 = highest priority)."])
end
