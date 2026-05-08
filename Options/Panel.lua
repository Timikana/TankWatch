local addonName, TW = ...
local L = TW.L

local CreateFrame = CreateFrame
local pairs, ipairs = pairs, ipairs

local panel
local refresh = function() if TW.RefreshAll then TW:RefreshAll() end end

-- ============================================================
-- "NEW" BADGE
-- ============================================================
local function markAsNew(widget, key)
    if not widget or not key then return widget end
    if not TW.IsFeatureNew or not TW:IsFeatureNew(key) then return widget end

    local badge = CreateFrame("Frame", nil, widget, "BackdropTemplate")
    badge:SetSize(38, 16)
    badge:SetPoint("BOTTOMLEFT", widget, "TOPLEFT", -3, 1)
    badge:SetFrameLevel((widget.GetFrameLevel and widget:GetFrameLevel() or 1) + 5)
    badge:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    badge:SetBackdropColor(0.95, 0.45, 0.05, 0.85)        -- orange fill
    badge:SetBackdropBorderColor(1, 0.85, 0.2, 1)         -- gold border

    local glow = badge:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.85, 0, 0.9)
    glow:SetPoint("CENTER", badge, "CENTER", 0, 0)
    glow:SetSize(58, 36)

    local text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetText("NEW")
    text:SetTextColor(1, 1, 1)
    text:SetPoint("CENTER")
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)

    local ag = glow:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.3); a:SetDuration(0.8); a:SetSmoothing("IN_OUT")
    ag:Play()

    local dismissed = false
    local function clear()
        if dismissed then return end
        dismissed = true
        if TW.MarkFeatureSeen then TW:MarkFeatureSeen(key) end
        if ag then ag:Stop() end
        badge:Hide()
    end

    pcall(function() widget:HookScript("OnEnter", clear) end)
    local typ = widget.GetObjectType and widget:GetObjectType() or ""
    if typ == "CheckButton" or typ == "Button" then
        pcall(function() widget:HookScript("OnClick", clear) end)
    end
    pcall(function() widget:HookScript("OnMouseUp", clear) end)
    return widget
end

-- ============================================================
-- WIDGET FACTORIES
-- ============================================================

local function makeSlider(parent, label, key, minV, maxV, step, x, y, width)
    local sl = CreateFrame("Frame", "TWOpt_"..key, parent, "MinimalSliderWithSteppersTemplate")
    sl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    sl:SetWidth(width or 200)
    sl.dbKey = key

    local function fmt(v)
        if step < 1 then return string.format("%.2f", v) end
        return tostring(math.floor(v + 0.5))
    end

    local formatters = {
        [MinimalSliderWithSteppersMixin.Label.Min] = function() return fmt(minV) end,
        [MinimalSliderWithSteppersMixin.Label.Max] = function() return fmt(maxV) end,
        [MinimalSliderWithSteppersMixin.Label.Top] = function(v) return label .. ": " .. fmt(v) end,
    }

    local numSteps = math.max(1, math.floor((maxV - minV) / step + 0.5))
    local function readDB()
        local v = TW:GetDB()[key]
        if type(v) ~= "number" then v = minV end
        if v < minV then v = minV elseif v > maxV then v = maxV end
        return v
    end

    sl:Init(readDB(), minV, maxV, numSteps, formatters)

    local event = (MinimalSliderWithSteppersMixin.Event
        and MinimalSliderWithSteppersMixin.Event.OnValueChanged) or "OnValueChanged"
    sl:RegisterCallback(event, function(_, value)
        if step < 1 then value = math.floor(value * 100 + 0.5) / 100
        else value = math.floor(value + 0.5) end
        TW:GetDB()[key] = value
        refresh()
    end, sl)

    sl.refresh = function() sl:Init(readDB(), minV, maxV, numSteps, formatters) end
    return sl
end

local function makeCheck(parent, label, key, x, y)
    local cb = CreateFrame("CheckButton", "TWOpt_"..key, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    cb:SetSize(24, 24)
    cb.Text:SetFontObject("GameFontHighlight")
    cb.Text:SetText(label)
    cb.dbKey = key
    cb:SetScript("OnClick", function(self)
        TW:GetDB()[key] = self:GetChecked() and true or false
        refresh()
    end)
    return cb
end

local function makeDropdown(parent, label, key, options, x, y, width)
    local labelFS = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelFS:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    labelFS:SetText(label)

    local dd = CreateFrame("DropdownButton", "TWOpt_DD_"..key, parent, "WowStyle1DropdownTemplate")
    dd:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -2)
    dd:SetWidth(width or 160)
    dd.dbKey = key
    dd._options = options

    dd:SetupMenu(function(_, rootDescription)
        for _, opt in ipairs(options) do
            rootDescription:CreateRadio(opt.text,
                function() return TW:GetDB()[key] == opt.value end,
                function()
                    TW:GetDB()[key] = opt.value
                    refresh()
                end)
        end
    end)
    dd.refresh = function() dd:GenerateMenu() end
    return dd
end

local POPUP_ITEM_H = 22
local POPUP_VISIBLE = 12

local function makeMediaDropdown(parent, label, key, mediaType, x, y, width)
    width = width or 180

    local labelFS = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelFS:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    labelFS:SetText(label)

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, 24)
    btn:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -4)
    btn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.06, 0.06, 0.08, 1)
    btn:SetBackdropBorderColor(0.35, 0.35, 0.40, 1)
    btn:HookScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.82, 0, 1) end)
    btn:HookScript("OnLeave", function(self) self:SetBackdropBorderColor(0.35, 0.35, 0.40, 1) end)
    btn.dbKey = key

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btnText:SetPoint("LEFT", btn, "LEFT", 6, 0)
    btnText:SetPoint("RIGHT", btn, "RIGHT", -16, 0)
    btnText:SetJustifyH("LEFT")

    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(14, 14)
    arrow:SetPoint("RIGHT", btn, "RIGHT", -2, 0)

    local previewBg = parent:CreateTexture(nil, "BACKGROUND")
    previewBg:SetPoint("LEFT", btn, "RIGHT", 12, 0)
    previewBg:SetSize(width + 30, 18)
    previewBg:SetColorTexture(0, 0, 0, 0.7)

    local previewBorder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    previewBorder:SetPoint("TOPLEFT", previewBg, "TOPLEFT", -1, 1)
    previewBorder:SetPoint("BOTTOMRIGHT", previewBg, "BOTTOMRIGHT", 1, -1)
    previewBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    previewBorder:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local previewTex, previewText
    if mediaType == "font" then
        previewText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        previewText:SetPoint("CENTER", previewBg, "CENTER", 0, 0)
        previewText:SetText("AaBb 123")
        previewText:SetTextColor(1, 0.82, 0)
    else
        previewTex = parent:CreateTexture(nil, "ARTWORK")
        previewTex:SetPoint("TOPLEFT", previewBg, "TOPLEFT", 1, -1)
        previewTex:SetPoint("BOTTOMRIGHT", previewBg, "BOTTOMRIGHT", -1, 1)
    end

    local function applyPreview(name)
        if mediaType == "font" then
            pcall(previewText.SetFont, previewText, TW:ResolveFont(name), 13, "")
        else
            previewTex:SetTexture(TW:ResolveTexture(name))
            previewTex:SetVertexColor(0.2, 0.6, 0.95, 1)
        end
    end

    local function listMedia()
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then return LSM:List(mediaType) end
        return { "Blizzard" }
    end

    local popupW = width + 40
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetSize(popupW, POPUP_ITEM_H * POPUP_VISIBLE + 12)
    popup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    popup:SetBackdropColor(0.03, 0.03, 0.05, 0.98)
    popup:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    popup:Hide()
    popup:EnableMouse(true)

    local scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", popup, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -28, 8)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(popupW - 36, 10)
    scroll:SetScrollChild(content)

    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(1)
    catcher:RegisterForClicks("AnyUp")
    catcher:Hide()
    catcher:SetScript("OnClick", function() popup:Hide() end)
    popup:HookScript("OnShow", function()
        catcher:Show()
        popup:SetFrameLevel(catcher:GetFrameLevel() + 10)
    end)
    popup:HookScript("OnHide", function() catcher:Hide() end)

    local itemPool = {}
    local function getItem(i)
        if itemPool[i] then return itemPool[i] end
        local it = CreateFrame("Button", nil, content)
        it:SetHeight(POPUP_ITEM_H)
        it:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(i - 1) * POPUP_ITEM_H)
        it:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * POPUP_ITEM_H)

        local hl = it:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints(it)
        hl:SetColorTexture(1, 0.82, 0, 0.18)
        hl:Hide()
        it:SetScript("OnEnter", function() hl:Show() end)
        it:SetScript("OnLeave", function() hl:Hide() end)

        if mediaType == "font" then
            local fs = it:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            fs:SetPoint("LEFT", it, "LEFT", 8, 0)
            fs:SetPoint("RIGHT", it, "RIGHT", -8, 0)
            fs:SetJustifyH("LEFT")
            it.fs = fs
        else
            local barBg = it:CreateTexture(nil, "BACKGROUND", nil, 1)
            barBg:SetPoint("LEFT", it, "LEFT", 6, 0)
            barBg:SetPoint("RIGHT", it, "RIGHT", -6, 0)
            barBg:SetHeight(16)
            barBg:SetColorTexture(0, 0, 0, 0.6)
            local bar = it:CreateTexture(nil, "ARTWORK")
            bar:SetPoint("TOPLEFT", barBg, "TOPLEFT", 1, -1)
            bar:SetPoint("BOTTOMRIGHT", barBg, "BOTTOMRIGHT", -1, 1)
            local nameFS = it:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nameFS:SetPoint("LEFT", barBg, "LEFT", 6, 0)
            nameFS:SetTextColor(1, 1, 1, 1)
            it.bar = bar
            it.nameFS = nameFS
        end
        itemPool[i] = it
        return it
    end

    local function rebuild()
        local list = listMedia()
        for i, name in ipairs(list) do
            local it = getItem(i)
            it:Show()
            if mediaType == "font" then
                pcall(it.fs.SetFont, it.fs, TW:ResolveFont(name), 13, "")
                it.fs:SetText(name)
            else
                it.bar:SetTexture(TW:ResolveTexture(name))
                it.bar:SetVertexColor(0.2, 0.6, 0.95, 1)
                it.nameFS:SetText(name)
            end
            it:SetScript("OnClick", function()
                TW:GetDB()[key] = name
                btnText:SetText(name)
                applyPreview(name)
                popup:Hide()
                refresh()
            end)
        end
        for i = #list + 1, #itemPool do itemPool[i]:Hide() end
        content:SetHeight(math.max(POPUP_ITEM_H, #list * POPUP_ITEM_H))
    end

    btn:SetScript("OnClick", function()
        if popup:IsShown() then
            popup:Hide()
        else
            rebuild()
            popup:ClearAllPoints()
            popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            popup:Show()
        end
    end)

    btn.refresh = function()
        local cur = TW:GetDB()[key] or "Blizzard"
        btnText:SetText(cur)
        applyPreview(cur)
    end
    btn.refresh()
    return btn
end

local function makeColorPicker(parent, label, dbKey, x, y)
    local lab
    if label and label ~= "" then
        lab = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lab:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        lab:SetText(label)
    end

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(28, 22)
    if lab then
        btn:SetPoint("TOPLEFT", lab, "BOTTOMLEFT", 0, -2)
    else
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end
    btn:RegisterForClicks("AnyUp")

    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(btn)
    border:SetColorTexture(0.55, 0.45, 0.10, 1)

    local swatch = btn:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    swatch:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    swatch:SetColorTexture(1, 1, 1, 1)

    btn:SetScript("OnEnter", function(self)
        border:SetColorTexture(1, 0.82, 0, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Click to choose a color"], 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        border:SetColorTexture(0.55, 0.45, 0.10, 1)
        GameTooltip:Hide()
    end)

    local function getColor()
        return TW:GetDB()[dbKey] or { r = 1, g = 1, b = 1, a = 1 }
    end
    local function refreshSwatch()
        local c = getColor()
        swatch:SetVertexColor(c.r or 1, c.g or 1, c.b or 1, c.a or 1)
    end
    btn.dbKey = dbKey
    btn.refresh = refreshSwatch
    refreshSwatch()

    btn:SetScript("OnClick", function()
        local c = getColor()
        local function setColor(r, g, b, a)
            TW:GetDB()[dbKey] = { r = r, g = g, b = b, a = a or 1 }
            refreshSwatch()
            refresh()
        end
        local function readAlpha()
            if ColorPickerFrame.GetColorAlpha then
                return ColorPickerFrame:GetColorAlpha() or 1
            elseif OpacitySliderFrame and OpacitySliderFrame:IsShown() then
                return OpacitySliderFrame:GetValue()
            end
            return 1
        end
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                hasOpacity = true,
                opacity = c.a or 1,
                r = c.r, g = c.g, b = c.b,
                swatchFunc = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    setColor(r, g, b, readAlpha())
                end,
                opacityFunc = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    setColor(r, g, b, readAlpha())
                end,
                cancelFunc = function(prev)
                    setColor(prev.r, prev.g, prev.b, prev.opacity or 1)
                end,
            })
        else
            ColorPickerFrame:SetColorRGB(c.r, c.g, c.b)
            ColorPickerFrame.hasOpacity = true
            ColorPickerFrame.opacity = c.a or 1
            ColorPickerFrame.previousValues = { r = c.r, g = c.g, b = c.b, opacity = c.a or 1 }
            ColorPickerFrame.func = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                setColor(r, g, b, ColorPickerFrame.opacity or 1)
            end
            ColorPickerFrame.opacityFunc = ColorPickerFrame.func
            ColorPickerFrame.cancelFunc = function(prev)
                setColor(prev.r, prev.g, prev.b, prev.opacity or 1)
            end
            ColorPickerFrame:Hide()
            ColorPickerFrame:Show()
        end
    end)

    return btn
end

-- Section header with title + thin gold separator line.
-- Both line endpoints anchored to parent at the same y to avoid diagonal/aliased rendering.
local function makeSection(parent, title, x, y)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    header:SetText(title)
    header:SetTextColor(1, 0.82, 0)

    local line = parent:CreateTexture(nil, "OVERLAY")
    line:SetHeight(1)
    line:SetColorTexture(1, 0.82, 0, 0.55)

    local function place()
        local w = header:GetStringWidth() or 0
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT",  parent, "TOPLEFT",  x + w + 10, y - 7)
        line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14,        y - 7)
    end
    place()
    C_Timer.After(0, place)
    return header
end

-- Hover tooltip helper. Hooks the widget AND known sub-controls of composite widgets.
local function addTooltip(widget, text)
    if not widget or not text or text == "" then return widget end
    local function show(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end
    local function hide() GameTooltip:Hide() end
    local function hook(f)
        if not f or not f.HookScript then return end
        f:HookScript("OnEnter", show)
        f:HookScript("OnLeave", hide)
    end
    hook(widget)
    hook(widget.Slider)
    hook(widget.Back)
    hook(widget.Forward)
    return widget
end

local function ANCHOR9()
    return {
        { text = L["Top Left"],     value = "TOPLEFT" },
        { text = L["Top"],          value = "TOP" },
        { text = L["Top Right"],    value = "TOPRIGHT" },
        { text = L["Left"],         value = "LEFT" },
        { text = L["Center"],       value = "CENTER" },
        { text = L["Right"],        value = "RIGHT" },
        { text = L["Bottom Left"],  value = "BOTTOMLEFT" },
        { text = L["Bottom"],       value = "BOTTOM" },
        { text = L["Bottom Right"], value = "BOTTOMRIGHT" },
    }
end

-- ============================================================
-- TABS — modern Blizzard bottom tabs (PanelTabButtonTemplate),
-- the same style used by CharacterFrame, SpellBookFrame, etc.
-- They hang from the bottom edge of the panel and don't overlap the portrait.
-- ============================================================
local function makeTab(parent, id, label, prevTab)
    local tab = CreateFrame("Button", "TWTab"..id, parent, "PanelTabButtonTemplate")
    tab:SetText(label)
    tab.id = id
    if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0) end
    if prevTab then
        tab:SetPoint("LEFT", prevTab, "RIGHT", 4, 0)
    else
        tab:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 10, 2)
    end
    return tab
end

local function styleTabSelected(tab, selected)
    if selected then
        if PanelTemplates_SelectTab then PanelTemplates_SelectTab(tab) end
    else
        if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(tab) end
    end
end

-- ============================================================
-- PAGE BUILDERS
-- ============================================================

local function buildLayoutPage(page)
    local y = -8

    -- ============ GENERAL ============
    makeSection(page, L["General"], 14, y); y = y - 22

    local btnMover = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    btnMover:SetSize(160, 22); btnMover:SetPoint("TOPLEFT", 14, y)
    btnMover:SetText(L["Unlock / Lock Mover"])
    btnMover:SetScript("OnClick", function() TW:ToggleMover() end)
    addTooltip(btnMover, L["Toggle a draggable handle on the tank container so you can move it on screen."])

    local label = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 184, y - 4)
    label:SetText(L["Test:"])

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

    local xs = 220
    for _, count in ipairs({ 0, 1, 2, 3, 4, 5, 6, 8 }) do
        local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        b:SetSize(34, 22)
        b:SetPoint("TOPLEFT", xs, y)
        b:SetText(count == 0 and L["Off"] or tostring(count))
        b._count = count
        b:SetScript("OnClick", function() TW:SetTestMode(count); refreshTestBtns() end)
        addTooltip(b, count == 0 and L["Stop the simulation."]
            or format(L["Simulate %d tank frame(s) with fake debuffs and HP."], count))
        testBtns[#testBtns + 1] = b
        xs = xs + 36
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

    y = y - 32

    -- Visibility scope dropdown
    addTooltip(markAsNew(makeDropdown(page, L["Show in"], "visibilityMode", {
        { text = L["Raid only"],           value = "RAID" },
        { text = L["Raid or 5-man"],       value = "GROUP" },
        { text = L["Always (incl. solo)"], value = "ALWAYS" },
    }, 14, y, 220), "v1.x_visibilityMode"),
        L["When TankWatch frames are visible: only in raid, in any group, or always."])

    -- Panel opacity slider (account-wide)
    local alphaSlider = CreateFrame("Frame", nil, page, "MinimalSliderWithSteppersTemplate")
    alphaSlider:SetWidth(220)
    alphaSlider:SetPoint("TOPLEFT", page, "TOPLEFT", 260, y + 18)
    local function fmtPct(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
    local alphaFormatters = {
        [MinimalSliderWithSteppersMixin.Label.Min] = function() return "20%" end,
        [MinimalSliderWithSteppersMixin.Label.Max] = function() return "100%" end,
        [MinimalSliderWithSteppersMixin.Label.Top] = function(v)
            return L["Panel opacity"] .. ": " .. fmtPct(v)
        end,
    }
    TankWatchDB = TankWatchDB or {}
    if TankWatchDB.panelAlpha == nil then TankWatchDB.panelAlpha = 0.8 end
    alphaSlider:Init(TankWatchDB.panelAlpha, 0.2, 1.0, 16, alphaFormatters)
    local alphaEvent = (MinimalSliderWithSteppersMixin.Event
        and MinimalSliderWithSteppersMixin.Event.OnValueChanged) or "OnValueChanged"
    alphaSlider:RegisterCallback(alphaEvent, function(_, v)
        v = math.floor(v * 20 + 0.5) / 20
        TankWatchDB.panelAlpha = v
        if panel then panel:SetAlpha(v) end
    end, alphaSlider)
    addTooltip(alphaSlider, L["Opacity of this options window. Saved account-wide."])

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
end

local function buildBarsPage(page)
    local y = -8

    -- ============ TEXTURES ============
    makeSection(page, L["Textures"], 14, y); y = y - 24
    addTooltip(makeMediaDropdown(page, L["Health Texture"], "healthTexture", "statusbar", 14, y, 180),
        L["Status bar texture used for the tank health bar."])

    -- ============ HEALTH COLOR ============
    y = y - 60
    makeSection(page, L["Health Color"], 14, y); y = y - 24
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

    -- ============ RANGE FADE ============
    y = y - 60
    makeSection(page, L["Range Fade"], 14, y); y = y - 24
    addTooltip(makeCheck(page, L["Fade out-of-range tanks"], "rangeFadeEnabled", 14, y),
        L["Reduce the alpha of tank frames whose unit is out of 40-yard range."])
    addTooltip(makeSlider(page, L["Out-of-range alpha"], "rangeFadeAlpha", 0.05, 1, 0.05, 260, y),
        L["Alpha applied to out-of-range tank frames."])
end

local function buildTextPage(page)
    local y = -8

    -- HP formats — PERCENT removed (UnitHealth is secret in 12.0, can't compute cur/max)
    local FORMATS = {
        { text = L["Current (50M)"],   value = "CURRENT" },
        { text = L["Current / Max"],   value = "CURRENT_MAX" },
    }

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
    y = y - 56
    addTooltip(makeDropdown(page, L["HP format"], "healthTextFormat", FORMATS, 14, y, 200),
        L["Format of the HP value. Percent is unavailable in 12.0 (secret-tagged HP)."])

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

local function buildAurasPage(page)
    local y = -8

    -- ============ DISPLAY ============
    makeSection(page, L["Display"], 14, y); y = y - 24
    addTooltip(makeCheck(page, L["Show Auras"], "showAuras", 14, y),
        L["Show the tank's boss-cast debuffs as icons on the frame."])
    addTooltip(makeCheck(page, L["Only debuffs with stacks"], "aurasOnlyStacks", 184, y),
        L["Hide debuffs that don't have a stack count (applications == 1)."])
    y = y - 30

    local note = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 14, y)
    note:SetWidth(680); note:SetJustifyH("LEFT")
    note:SetText(L["By default only boss-cast HARMFUL auras show. Use the Filters tab to whitelist M+ debuffs or blacklist noise."])
    y = y - 32

    -- ============ SIZE ============
    makeSection(page, L["Size"], 14, y); y = y - 24
    addTooltip(makeSlider(page, L["Max Count"], "aurasMaxCount", 1, 10, 1, 14, y),
        L["Maximum number of debuff icons shown per tank frame."])
    addTooltip(makeSlider(page, L["Size"], "aurasSize", 16, 64, 1, 260, y),
        L["Size of each debuff icon in pixels."])
    y = y - 56
    addTooltip(makeSlider(page, L["Spacing"], "aurasSpacing", 0, 12, 1, 14, y),
        L["Gap between debuff icons in pixels."])

    -- ============ LAYOUT ============
    y = y - 60
    makeSection(page, L["Layout"], 14, y); y = y - 24
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
end

-- ============================================================
-- SPELL LIST WIDGET (used by Filters tab)
-- ============================================================
local function getSpellInfo(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if info then return info.name, info.iconID end
    end
    if GetSpellInfo then
        local n, _, ic = GetSpellInfo(id)
        return n, ic
    end
    return nil, nil
end

local ROW_H = 22
local function makeSpellList(parent, dbKey, title, x, y, w, h)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", x, y)
    header:SetText(title)
    header:SetTextColor(1, 0.82, 0)

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", x, y - 18)
    frame:SetSize(w, h)
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.05, 0.05, 0.07, 0.9)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -24, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(w - 32, 10)
    scroll:SetScrollChild(content)

    local pool = {}
    local function getRow(i)
        if pool[i] then return pool[i] end
        local r = CreateFrame("Frame", nil, content)
        r:SetSize(w - 32, ROW_H)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        local ic = r:CreateTexture(nil, "ARTWORK")
        ic:SetSize(18, 18); ic:SetPoint("LEFT", 2, 0)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", ic, "RIGHT", 6, 0)
        fs:SetPoint("RIGHT", r, "RIGHT", -22, 0)
        fs:SetJustifyH("LEFT")
        local rm = CreateFrame("Button", nil, r, "UIPanelCloseButton")
        rm:SetSize(18, 18); rm:SetPoint("RIGHT", 0, 0)
        r.icon, r.text, r.rm = ic, fs, rm
        pool[i] = r
        return r
    end

    local refresh
    local function rebuild()
        local db = TW:GetDB()
        local t = db[dbKey] or {}
        local ids = {}
        for id in pairs(t) do ids[#ids + 1] = id end
        table.sort(ids)
        for i = 1, #ids do
            local id = ids[i]
            local r = getRow(i)
            r:Show()
            local n, ic = getSpellInfo(id)
            r.icon:SetTexture(ic or 134400)
            r.text:SetText((n or "Unknown") .. "  |cffaaaaaa(" .. id .. ")|r")
            r.rm:SetScript("OnClick", function()
                TW:GetDB()[dbKey][id] = nil
                refresh()
                if TW.RefreshAll then TW:RefreshAll() end
            end)
        end
        for i = #ids + 1, #pool do pool[i]:Hide() end
        content:SetHeight(math.max(ROW_H, #ids * ROW_H))
    end
    refresh = rebuild

    local addLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("TOPLEFT", x, y - 18 - h - 4)
    addLabel:SetText(L["Spell ID:"])
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(80, 22)
    edit:SetPoint("LEFT", addLabel, "RIGHT", 8, 0)
    edit:SetAutoFocus(false)
    edit:SetNumeric(true)

    local addBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addBtn:SetSize(60, 22)
    addBtn:SetPoint("LEFT", edit, "RIGHT", 6, 0)
    addBtn:SetText(L["Add"])
    local function doAdd()
        local id = tonumber(edit:GetText())
        if not id or id <= 0 then return end
        local n = getSpellInfo(id)
        if not n then
            print("|cff00ff96TankWatch:|r " .. format(L["unknown spell ID %d"], id))
            return
        end
        local db = TW:GetDB()
        db[dbKey] = db[dbKey] or {}
        db[dbKey][id] = true
        edit:SetText("")
        refresh()
        if TW.RefreshAll then TW:RefreshAll() end
    end
    addBtn:SetScript("OnClick", doAdd)
    edit:SetScript("OnEnterPressed", function(self) doAdd(); self:ClearFocus() end)

    return { refresh = refresh }
end

local function makeNameList(parent, dbKey, title, x, y, w, h)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", x, y); header:SetText(title)

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", x, y - 16)
    frame:SetSize(w, h)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
    })
    frame:SetBackdropColor(0.05, 0.05, 0.07, 0.9)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4); scroll:SetPoint("BOTTOMRIGHT", -24, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(w - 32, 10); scroll:SetScrollChild(content)

    local pool = {}
    local function getRow(i)
        if pool[i] then return pool[i] end
        local r = CreateFrame("Frame", nil, content)
        r:SetSize(w - 32, ROW_H)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 6, 0); fs:SetPoint("RIGHT", -22, 0); fs:SetJustifyH("LEFT")
        local rm = CreateFrame("Button", nil, r, "UIPanelCloseButton")
        rm:SetSize(18, 18); rm:SetPoint("RIGHT", 0, 0)
        r.text, r.rm = fs, rm
        pool[i] = r
        return r
    end

    local refresh
    local function rebuild()
        local db = TW:GetDB()
        local t = db[dbKey] or {}
        local names = {}
        for n in pairs(t) do names[#names + 1] = n end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        for i, name in ipairs(names) do
            local r = getRow(i); r:Show()
            r.text:SetText(name)
            r.rm:SetScript("OnClick", function()
                TW:GetDB()[dbKey][name] = nil
                refresh(); if TW.RefreshTanks then TW:RefreshTanks() end
            end)
        end
        for i = #names + 1, #pool do pool[i]:Hide() end
        content:SetHeight(math.max(ROW_H, #names * ROW_H))
    end
    refresh = rebuild

    local addLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("TOPLEFT", x, y - 16 - h - 4)
    addLabel:SetText(L["Player name:"])
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(140, 22)
    edit:SetPoint("LEFT", addLabel, "RIGHT", 8, 0)
    edit:SetAutoFocus(false)

    local addBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addBtn:SetSize(60, 22)
    addBtn:SetPoint("LEFT", edit, "RIGHT", 6, 0)
    addBtn:SetText(L["Add"])
    local function doAdd()
        local n = (edit:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if n == "" then return end
        local db = TW:GetDB()
        db[dbKey] = db[dbKey] or {}
        db[dbKey][n] = true
        edit:SetText("")
        refresh(); if TW.RefreshTanks then TW:RefreshTanks() end
    end
    addBtn:SetScript("OnClick", doAdd)
    edit:SetScript("OnEnterPressed", function(self) doAdd(); self:ClearFocus() end)

    return { refresh = refresh }
end

local function buildFiltersPage(page)
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

    addTooltip(markAsNew(makeDropdown(page, L["Filter mode"], "auraFilterMode", {
        { text = L["All harmful debuffs"],  value = "ALL" },
        { text = L["Boss-cast only"],       value = "BOSS" },
        { text = L["Whitelist only"],       value = "WHITELIST" },
    }, 14, y, 220), "v1.x_filterMode"),
        L["Which debuffs to show: every HARMFUL aura, only those cast by bosses, or only spells in your whitelist."])
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

-- ============================================================
-- POPUPS (lazy: mutating StaticPopupDialogs at file load taints in 12.0)
-- ============================================================
local _popupsRegistered = false
local function ensurePopups()
    if _popupsRegistered then return end
    StaticPopupDialogs = StaticPopupDialogs or {}
    StaticPopupDialogs["TANKWATCH_PROFILE_NAME"] = {
        text         = "%s",
        button1      = OKAY or "OK",
        button2      = CANCEL or "Cancel",
        hasEditBox   = true,
        editBoxWidth = 240,
        timeout      = 0, whileDead = true, hideOnEscape = true,
        OnShow   = function(self) self.editBox:SetText(""); self.editBox:SetFocus() end,
        OnAccept = function(self) if self.data and self.data.onAccept then self.data.onAccept(self.editBox:GetText()) end end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            if parent.data and parent.data.onAccept then parent.data.onAccept(self:GetText()) end
            parent:Hide()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    }
    StaticPopupDialogs["TANKWATCH_CONFIRM"] = {
        text         = "%s",
        button1      = YES or "Yes",
        button2      = NO  or "No",
        timeout      = 0, whileDead = true, hideOnEscape = true,
        OnAccept     = function(self) if self.data and self.data.onAccept then self.data.onAccept() end end,
    }
    _popupsRegistered = true
end

local function askName(prompt, onAccept)
    ensurePopups()
    local d = StaticPopup_Show("TANKWATCH_PROFILE_NAME", prompt)
    if d then d.data = { onAccept = onAccept } end
end

local function askConfirm(prompt, onAccept)
    ensurePopups()
    local d = StaticPopup_Show("TANKWATCH_CONFIRM", prompt)
    if d then d.data = { onAccept = onAccept } end
end

-- ============================================================
-- PROFILES PAGE
-- ============================================================
local profileDropdownRefresh

local function buildProfilesPage(page)
    local y = -10

    -- Character label
    local charLabel = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    charLabel:SetPoint("TOPLEFT", 14, y)
    charLabel:SetText(L["Character:"] .. " |cffffffff" .. (TW:GetCharKey()) .. "|r")

    y = y - 24

    -- Active profile dropdown
    local labelFS = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelFS:SetPoint("TOPLEFT", 14, y)
    labelFS:SetText(L["Active profile"])

    local dd = CreateFrame("DropdownButton", "TWOpt_DD_activeProfile", page, "WowStyle1DropdownTemplate")
    dd:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -2)
    dd:SetWidth(220)

    dd:SetupMenu(function(_, rootDescription)
        for _, name in ipairs(TW:ListProfiles()) do
            rootDescription:CreateRadio(name,
                function() return name == TW:GetActiveProfileName() end,
                function()
                    TW:SetActiveProfile(name)
                    if panel and panel.refreshAll then panel.refreshAll() end
                end)
        end
    end)
    profileDropdownRefresh = function() dd:GenerateMenu() end
    profileDropdownRefresh()

    y = y - 56

    -- New / Reset / Delete row
    local btnNew = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    btnNew:SetSize(110, 22)
    btnNew:SetPoint("TOPLEFT", 14, y)
    btnNew:SetText(L["New..."])
    btnNew:SetScript("OnClick", function()
        askName(L["Name of the new profile (copies current settings):"], function(name)
            name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" then return end
            local ok, err = TW:CreateProfile(name, TW:GetActiveProfileName())
            if ok then
                TW:SetActiveProfile(name)
                profileDropdownRefresh()
                if panel and panel.refreshAll then panel.refreshAll() end
                print("|cff00ff96TankWatch:|r " .. format(L["profile '%s' created"], name))
            else
                print("|cff00ff96TankWatch:|r " .. tostring(err))
            end
        end)
    end)
    addTooltip(btnNew, L["Create a new profile copying the currently active settings."])

    local btnReset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    btnReset:SetSize(110, 22)
    btnReset:SetPoint("LEFT", btnNew, "RIGHT", 6, 0)
    btnReset:SetText(L["Reset"])
    btnReset:SetScript("OnClick", function()
        askConfirm(format(L["Reset profile '%s' to defaults?"], TW:GetActiveProfileName()), function()
            TW:ResetCurrentProfile()
            if panel and panel.refreshAll then panel.refreshAll() end
            if TW.RefreshAll then TW:RefreshAll() end
        end)
    end)
    addTooltip(btnReset, L["Reset the active profile back to default values."])

    local btnDelete = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    btnDelete:SetSize(110, 22)
    btnDelete:SetPoint("LEFT", btnReset, "RIGHT", 6, 0)
    btnDelete:SetText(L["Delete"])
    btnDelete:SetScript("OnClick", function()
        local cur = TW:GetActiveProfileName()
        if cur == "Default" then
            print("|cff00ff96TankWatch:|r " .. L["cannot delete Default"]); return
        end
        askConfirm(format(L["Delete profile '%s'?"], cur), function()
            TW:DeleteProfile(cur)
            TW:SetActiveProfile("Default")
            profileDropdownRefresh()
            if panel and panel.refreshAll then panel.refreshAll() end
        end)
    end)
    addTooltip(btnDelete, L["Delete the active profile (Default cannot be deleted)."])

    y = y - 36

    -- Export
    local exportLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    exportLabel:SetPoint("TOPLEFT", 14, y)
    exportLabel:SetText(L["Export"])
    exportLabel:SetTextColor(1, 0.82, 0)

    y = y - 18

    local exportScroll = CreateFrame("ScrollFrame", nil, page, "InputScrollFrameTemplate")
    exportScroll:SetPoint("TOPLEFT", 14, y)
    exportScroll:SetSize(560, 80)
    local exportEdit = exportScroll.EditBox
    exportEdit:SetMaxLetters(0)
    exportEdit:SetFontObject("ChatFontSmall")
    exportEdit:SetWidth(540)
    exportEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if exportScroll.CharCount then exportScroll.CharCount:Hide() end
    if exportEdit.SetCountInvisibleLetters then exportEdit:SetCountInvisibleLetters(true) end

    local function refreshExport()
        local s = TW:ExportProfile(TW:GetActiveProfileName())
        exportEdit:SetText(s or "")
    end
    refreshExport()

    local btnRefreshExport = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    btnRefreshExport:SetSize(140, 22)
    btnRefreshExport:SetPoint("TOPLEFT", exportScroll, "BOTTOMLEFT", 0, -4)
    btnRefreshExport:SetText(L["Refresh export"])
    btnRefreshExport:SetScript("OnClick", refreshExport)
    addTooltip(btnRefreshExport, L["Re-build the export string from the current profile values."])

    local btnSelectAll = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    btnSelectAll:SetSize(110, 22)
    btnSelectAll:SetPoint("LEFT", btnRefreshExport, "RIGHT", 6, 0)
    btnSelectAll:SetText(L["Select all"])
    btnSelectAll:SetScript("OnClick", function()
        exportEdit:SetFocus(); exportEdit:HighlightText()
    end)
    addTooltip(btnSelectAll, L["Highlight the export text so you can Ctrl+C to copy it."])

    y = y - 116

    -- Import
    local importLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    importLabel:SetPoint("TOPLEFT", 14, y)
    importLabel:SetText(L["Import"])
    importLabel:SetTextColor(1, 0.82, 0)

    y = y - 18

    local importScroll = CreateFrame("ScrollFrame", nil, page, "InputScrollFrameTemplate")
    importScroll:SetPoint("TOPLEFT", 14, y)
    importScroll:SetSize(560, 80)
    local importEdit = importScroll.EditBox
    importEdit:SetMaxLetters(0)
    importEdit:SetFontObject("ChatFontSmall")
    importEdit:SetWidth(540)
    importEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if importScroll.CharCount then importScroll.CharCount:Hide() end
    if importEdit.SetCountInvisibleLetters then importEdit:SetCountInvisibleLetters(true) end

    local btnImport = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    btnImport:SetSize(220, 22)
    btnImport:SetPoint("TOPLEFT", importScroll, "BOTTOMLEFT", 0, -4)
    btnImport:SetText(L["Import as new profile..."])
    btnImport:SetScript("OnClick", function()
        local raw = importEdit:GetText() or ""
        if raw:gsub("%s", "") == "" then
            print("|cff00ff96TankWatch:|r " .. L["import box is empty"]); return
        end
        askName(L["Name for the imported profile:"], function(name)
            name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" then return end
            local ok, err = TW:ImportProfile(name, raw)
            if ok then
                TW:SetActiveProfile(name)
                profileDropdownRefresh()
                refreshExport()
                if panel and panel.refreshAll then panel.refreshAll() end
                print("|cff00ff96TankWatch:|r " .. format(L["profile '%s' imported"], name))
            else
                print("|cff00ff96TankWatch:|r " .. L["import failed:"] .. " " .. tostring(err))
            end
        end)
    end)
    addTooltip(btnImport, L["Decode the export string and create a new profile from it."])

    page._refreshProfiles = function()
        profileDropdownRefresh()
        refreshExport()
        charLabel:SetText(L["Character:"] .. " |cffffffff" .. TW:GetCharKey() .. "|r")
    end
end

local function buildAboutPage(page)
    local version = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
    local author  = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Author")  or "Timikana"

    -- Logo (top left)
    local logo = page:CreateTexture(nil, "ARTWORK")
    logo:SetSize(140, 140)
    logo:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -14)
    logo:SetTexture("Interface\\AddOns\\TankWatch\\logo.png")

    -- Right column anchored to logo
    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 16, -4)
    title:SetText("|cff00ff96TankWatch|r  v" .. version)

    local sub = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sub:SetWidth(380); sub:SetJustifyH("LEFT")
    sub:SetText(L["See every tank in your group with their boss-cast debuffs and stack counts."])

    local byLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    byLabel:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
    byLabel:SetText(L["Author:"] .. " |cffffffff" .. author .. "|r")

    -- URL field
    local function urlField(yOff, label, url)
        local lab = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lab:SetPoint("TOPLEFT", 14, yOff)
        lab:SetText(label)

        local eb = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
        eb:SetSize(440, 22)
        eb:SetPoint("TOPLEFT", lab, "BOTTOMLEFT", 6, -4)
        eb:SetAutoFocus(false)
        eb:SetFontObject("GameFontHighlightSmall")
        eb:SetText(url)
        eb:SetCursorPosition(0)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
        eb:SetScript("OnMouseDown", function(self) self:HighlightText(); self:SetFocus() end)
        return eb
    end

    urlField(-170, "|cffffffff" .. L["GitHub repo:"]    .. "|r", "https://github.com/Timikana/TankWatch")
    urlField(-220, "|cffffffff" .. L["Report a bug:"]   .. "|r", "https://github.com/Timikana/TankWatch/issues")
    urlField(-270, "|cfff16436" .. L["CurseForge:"]     .. "|r", "https://www.curseforge.com/wow/addons/tankwatch")
    urlField(-320, "|cffb371ff" .. L["Wago:"]           .. "|r", "https://addons.wago.io/addons/tankwatch")

    local cmdHeader = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cmdHeader:SetPoint("TOPLEFT", 14, -380)
    cmdHeader:SetText(L["Slash commands"])
    cmdHeader:SetTextColor(1, 0.82, 0)

    local cmds = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cmds:SetPoint("TOPLEFT", cmdHeader, "BOTTOMLEFT", 0, -6)
    cmds:SetWidth(560); cmds:SetJustifyH("LEFT"); cmds:SetSpacing(3)
    cmds:SetText(
        "|cffffff00/tw|r — " .. L["open options"] .. "\n" ..
        "|cffffff00/tw config|r |cff888888(" .. L["alias"] .. ")|r — " .. L["open options"] .. "\n" ..
        "|cffffff00/tw options|r |cff888888(" .. L["alias"] .. ")|r — " .. L["open options"] .. "\n" ..
        "|cffffff00/tw mover|r — " .. L["toggle mover"] .. "\n" ..
        "|cffffff00/tw test N|r — " .. L["simulate N tanks (0-8)"] .. "\n" ..
        "|cffffff00/tw reset|r — " .. L["reset all settings + reload"] .. "\n" ..
        "|cffffff00/tw debug|r — " .. L["print roster role/maintank info"] .. "\n" ..
        "|cffffff00/tw auradebug|r — " .. L["print every HARMFUL aura on each tank unit"] .. "\n" ..
        "|cffffff00/tankwatch|r — " .. L["long alias for /tw"]
    )

    local hint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 14, 12)
    hint:SetText(L["Click a URL to select it, then Ctrl+C to copy."])
end

-- ============================================================
-- BUILD
-- ============================================================

local function build()
    panel = CreateFrame("Frame", "TankWatchOptions", UIParent, "PortraitFrameTemplate")
    panel:SetSize(720, 620)
    panel:SetPoint("CENTER")
    panel:SetMovable(true); panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetFrameStrata("HIGH")
    panel:Hide()
    panel:SetClampedToScreen(true)

    -- Close on ESC
    tinsert(UISpecialFrames, "TankWatchOptions")

    if panel.SetTitle then panel:SetTitle(L["TankWatch — Options"]) end
    if panel.SetPortraitToAsset then
        panel:SetPortraitToAsset("Interface\\AddOns\\TankWatch\\logo.png")
    end

    local pageHolder = CreateFrame("Frame", nil, panel)
    pageHolder:SetPoint("TOPLEFT", 8, -60)
    pageHolder:SetPoint("BOTTOMRIGHT", -8, 8)

    -- Panel opacity (account-wide preference)
    TankWatchDB = TankWatchDB or {}
    if TankWatchDB.panelAlpha == nil then TankWatchDB.panelAlpha = 0.8 end
    panel:SetAlpha(TankWatchDB.panelAlpha)

    local pages = {}
    local function newPage(name)
        local sf = CreateFrame("ScrollFrame", "TWScroll_"..name, pageHolder, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", pageHolder, "TOPLEFT", 0, 0)
        sf:SetPoint("BOTTOMRIGHT", pageHolder, "BOTTOMRIGHT", -24, 0)
        sf:Hide()

        local content = CreateFrame("Frame", nil, sf)
        content:SetSize(680, 900)
        sf:SetScrollChild(content)
        sf.content = content
        return sf
    end

    local function autoFitPage(sf)
        C_Timer.After(0, function()
            local content = sf.content
            if not content or not content:GetTop() then return end
            local top = content:GetTop()
            local lowest = top
            for _, child in ipairs({content:GetChildren()}) do
                if child:IsShown() then
                    local b = child:GetBottom()
                    if b and b < lowest then lowest = b end
                end
            end
            for _, region in ipairs({content:GetRegions()}) do
                if region:IsShown() then
                    local b = region:GetBottom()
                    if b and b < lowest then lowest = b end
                end
            end
            local used = math.max(50, top - lowest + 16)
            local viewportH = sf:GetHeight()
            content:SetHeight(math.max(used, viewportH))
            local sb = sf.ScrollBar or _G[sf:GetName() .. "ScrollBar"]
            if sb then sb:SetShown(used > viewportH + 1) end
        end)
    end

    pages.layout   = newPage("layout");   buildLayoutPage(pages.layout.content);     autoFitPage(pages.layout)
    pages.bars     = newPage("bars");     buildBarsPage(pages.bars.content);         autoFitPage(pages.bars)
    pages.text     = newPage("text");     buildTextPage(pages.text.content);         autoFitPage(pages.text)
    pages.auras    = newPage("auras");    buildAurasPage(pages.auras.content);       autoFitPage(pages.auras)
    pages.filters  = newPage("filters");  buildFiltersPage(pages.filters.content);   autoFitPage(pages.filters)
    pages.profiles = newPage("profiles"); buildProfilesPage(pages.profiles.content); autoFitPage(pages.profiles)
    pages.about    = newPage("about");    buildAboutPage(pages.about.content);       autoFitPage(pages.about)

    local tabs = {
        { id = "layout",   label = L["Layout"] },
        { id = "bars",     label = L["Bars"] },
        { id = "text",     label = L["Text"] },
        { id = "auras",    label = L["Auras"] },
        { id = "filters",  label = L["Filters"] },
        { id = "profiles", label = L["Profiles"] },
        { id = "about",    label = L["About"] },
    }
    local tabBtns = {}
    local function selectTab(id)
        for _, p in pairs(pages) do p:Hide() end
        if pages[id] then pages[id]:Show() end
        for _, t in ipairs(tabBtns) do
            styleTabSelected(t, t.id == id)
        end
    end

    for i, t in ipairs(tabs) do
        local b = makeTab(panel, t.id, t.label, tabBtns[i - 1])
        b:SetScript("OnClick", function() selectTab(t.id) end)
        tabBtns[#tabBtns + 1] = b
    end

    panel.refreshAll = function()
        local db = TW:GetDB()
        local function walk(f)
            for _, child in ipairs({f:GetChildren()}) do
                if child.dbKey then
                    if child.SetChecked then
                        child:SetChecked(db[child.dbKey] and true or false)
                    elseif child.refresh then
                        child:refresh()
                    end
                end
                walk(child)
            end
        end
        walk(pageHolder)
        if pages.profiles and pages.profiles.content and pages.profiles.content._refreshProfiles then
            pages.profiles.content._refreshProfiles()
        end
        if pages.filters and pages.filters.content and pages.filters.content._refreshFilters then
            pages.filters.content._refreshFilters()
        end
    end

    selectTab("layout")
end

function TW:ToggleOptions()
    if not panel then build() end
    if panel:IsShown() then panel:Hide()
    else panel.refreshAll(); panel:Show() end
end

function TW:RegisterBlizzardSettings()
    if TW._settingsCategoryID or not Settings or not Settings.RegisterCanvasLayoutCategory then
        return
    end
    local host = CreateFrame("Frame")
    host.name = "TankWatch"

    local title = host:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("TankWatch")

    local version = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
    local sub = host:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sub:SetWidth(540); sub:SetJustifyH("LEFT")
    sub:SetText(format(L["Tank visibility with boss-cast debuff stack tracking — v%s\nClick the button below to open the TankWatch configuration panel."], version))

    local btn = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
    btn:SetSize(220, 26)
    btn:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
    btn:SetText(L["Open TankWatch options"])
    btn:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if not panel or not panel:IsShown() then TW:ToggleOptions() end
    end)

    local hint = host:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -10)
    hint:SetText(L["You can also use the slash command: /tw"])

    local category = Settings.RegisterCanvasLayoutCategory(host, "TankWatch")
    category.ID = "TankWatch"
    Settings.RegisterAddOnCategory(category)
    TW._settingsCategoryID = category:GetID()
end
