local addonName, TW = ...
local L = TW.L
local format = string.format

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

function TW.OptPages.buildLayout(page)
    local y = -8

    -- ============ GENERAL ============
    makeSection(page, L["General"], 14, y); y = y - 22

    local btnMover = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    btnMover:SetSize(160, 22); btnMover:SetPoint("TOPLEFT", 14, y)
    btnMover:SetText(L["Unlock / Lock Mover"])
    btnMover:SetScript("OnClick", function() TW:ToggleMover() end)
    addTooltip(btnMover, L["Toggle a draggable handle on the tank container so you can move it on screen."])
    _registerInSection(btnMover)

    local label = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 184, y - 4)
    label:SetText(L["Test:"])
    _registerInSection(label)

    local function currentTestCount()
        local n = 0
        for i = 1, (TW.MAX_TANKS or 8) do
            if TW.TankFrames and TW.TankFrames[i] and TW.TankFrames[i]._testMode then n = n + 1 end
        end
        return n
    end

    local testBtns = {}
    local function refreshTestBtns()
        local n = currentTestCount()
        for _, b in ipairs(testBtns) do
            if b._count == n then b:LockHighlight() else b:UnlockHighlight() end
        end
    end

    -- Chain all test buttons relative to each other so the auto-flow doesn't
    -- separate them when the panel is resized (Off stays TOPLEFT to page, the
    -- numeric buttons follow Off's RIGHT edge).
    local prevB
    for _, count in ipairs({ 0, 1, 2, 3, 4, 5, 6, 8 }) do
        local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        local bw = (count == 0) and 44 or 30
        b:SetSize(bw, 22)
        if prevB then
            b:SetPoint("LEFT", prevB, "RIGHT", 4, 0)
        else
            b:SetPoint("TOPLEFT", page, "TOPLEFT", 220, y)
        end
        b:SetText(count == 0 and L["Off"] or tostring(count))
        b._count = count
        b:SetScript("OnClick", function() TW:SetTestMode(count); refreshTestBtns() end)
        addTooltip(b, count == 0 and L["Stop the simulation."]
            or format(L["Simulate %d tank frame(s) with fake debuffs and HP."], count))
        testBtns[#testBtns + 1] = b
        _registerInSection(b)
        prevB = b
    end
    refreshTestBtns()

    y = y - 30
    addTooltip(makeCheck(page, L["Enable"], "enabled", 14, y),
        L["Master switch for the addon. When off, TankWatch frames stay hidden."])

    -- Minimap icon checkbox (account-wide, not per-profile)
    local cbMini = CreateFrame("CheckButton", "TWOpt_minimapIcon", page, "UICheckButtonTemplate")
    cbMini:SetSize(24, 24)
    cbMini.Text:SetFontObject("GameFontHighlight")
    cbMini:SetPoint("TOPLEFT", page, "TOPLEFT", 184, y)
    cbMini.Text:SetText(L["Show minimap button"])
    cbMini:SetScript("OnShow", function(self)
        local g = TW:GetGlobalDB()
        self:SetChecked(not (g.minimap and g.minimap.hide))
    end)
    cbMini:SetScript("OnClick", function(self)
        local g = TW:GetGlobalDB()
        g.minimap = g.minimap or {}
        g.minimap.hide = not self:GetChecked()
        if TW.UpdateMinimapButton then TW:UpdateMinimapButton() end
    end)
    cbMini.refresh = function()
        local g = TW:GetGlobalDB()
        cbMini:SetChecked(not (g.minimap and g.minimap.hide))
    end
    addTooltip(cbMini, L["Show a minimap button. Left-click: options, right-click: toggle mover."])
    _registerInSection(cbMini)

    y = y - 32

    -- Visibility scope dropdown
    addTooltip(markAsNew(makeDropdown(page, L["Show in"], "visibilityMode", {
        { text = L["Raid only"],           value = "RAID" },
        { text = L["Raid or 5-man"],       value = "GROUP" },
        { text = L["Always (incl. solo)"], value = "ALWAYS" },
    }, 14, y, 220), "v1.x_visibilityMode"),
        L["When TankWatch frames are visible: only in raid, in any group, or always."])

    -- Compact mode toggle + sub-option (also reachable via Profiles > Presets).
    -- The class-icon checkbox is auto-enabled/disabled based on compactMode.
    local cbCompact = makeCheck(page, L["Compact mode (debuffs only)"], "compactMode", 280, y)
    addTooltip(markAsNew(cbCompact, "v1.3_compactMode"),
        L["Hide health/power/absorb bars and texts. Only the debuff icons remain (with the class icon if enabled below)."])

    local cbClassIcon = makeCheck(page, L["Show class icon"], "showClassIcon", 300, y - 22)
    addTooltip(markAsNew(cbClassIcon, "v1.3_showClassIcon"),
        L["Show a small class icon glued to the left of the debuff row. Only available in compact mode."])

    local function syncClassIconEnable()
        local on = cbCompact:GetChecked()
        if on then
            cbClassIcon:Enable()
            cbClassIcon.Text:SetTextColor(1, 1, 1)
        else
            cbClassIcon:Disable()
            cbClassIcon.Text:SetTextColor(0.5, 0.5, 0.5)
        end
    end
    cbCompact:HookScript("OnClick", function()
        syncClassIconEnable()
        if TW.RefreshAll then TW:RefreshAll() end
    end)
    cbCompact:HookScript("OnShow", syncClassIconEnable)
    syncClassIconEnable()

    -- ============ POSITION ============
    y = y - 60
    makeSection(page, L["Position"], 14, y); y = y - 24

    addTooltip(makeDropdown(page, L["Anchor"], "anchor", ANCHOR9(), 14, y),
        L["Anchor point on the screen used as origin for the X/Y offsets."])
    addTooltip(makeDropdown(page, L["Grow Direction"], "growDirection", {
        { text = L["Down"], value = "DOWN" }, { text = L["Up"], value = "UP" },
    }, 260, y), L["Direction additional tank frames stack from the first one."])
    y = y - 56

    addTooltip(makeSlider(page, L["Offset X"], "anchorX", -1500, 1500, 1, 14, y),
        L["Horizontal offset from the anchor point."])
    addTooltip(makeSlider(page, L["Offset Y"], "anchorY", -1500, 1500, 1, 260, y),
        L["Vertical offset from the anchor point."])

    -- ============ DIMENSIONS ============
    y = y - 60
    makeSection(page, L["Dimensions"], 14, y); y = y - 24

    addTooltip(makeSlider(page, L["Width"],  "frameWidth",  100, 400, 1, 14, y),
        L["Width of each tank frame in pixels."])
    addTooltip(makeSlider(page, L["Height"], "frameHeight",  20, 100, 1, 260, y),
        L["Height of each tank frame in pixels."])
    y = y - 56
    addTooltip(makeSlider(page, L["Spacing"], "frameSpacing", 0, 40, 1, 14, y),
        L["Vertical gap between stacked tank frames."])
    addTooltip(makeSlider(page, L["Scale"],  "frameScale", 0.5, 2.0, 0.05, 260, y),
        L["Overall scale of all tank frames."])

    -- ============ RANGE FADE (moved from Bars) ============
    y = y - 60
    makeSection(page, L["Range Fade"], 14, y); y = y - 24
    addTooltip(makeCheck(page, L["Fade out-of-range tanks"], "rangeFadeEnabled", 14, y),
        L["Reduce the alpha of tank frames whose unit is out of 40-yard range."])
    addTooltip(makeSlider(page, L["Out-of-range alpha"], "rangeFadeAlpha", 0.05, 1, 0.05, 260, y),
        L["Alpha applied to out-of-range tank frames."])
end
