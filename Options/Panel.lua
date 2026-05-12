local addonName, TW = ...
local L = TW.L

local CreateFrame = CreateFrame
local pairs, ipairs = pairs, ipairs

local panel
local refresh = function() if TW.RefreshAll then TW:RefreshAll() end end

-- Tracks the section currently being built. Each widget factory tags
-- its widget with this so collapsable sections know what to hide.
-- ============================================================
-- SECTION SYSTEM (port of BossWatch's container-based collapse)
-- Each section is a Frame chained TOPLEFT→prev.BOTTOMLEFT. Widgets
-- get reparented to that container. Collapsing shrinks the container,
-- and everything below slides up automatically thanks to the chain.
-- ============================================================
local _currentSection   = nil
local _lastSectionOnPage = {}   -- [pageContent] = last section built
local _allSectionsOnPage = {}   -- [pageContent] = { sec1, sec2, ... } in order

-- Tab badge wiring: populated when tabs are created. Search uses it to
-- decorate tab labels with hit counts.
local _searchTabRefs = {}

-- Forward decl: actual implementation lives inside build() so it can close
-- over `pages`, `selectTab`, the results page, etc. The search box just
-- calls _applySearch() which delegates here.
local _searchImpl = function() end
local function _applySearch(q) return _searchImpl(q) end

local SECTION_GAP      = 28
local COLLAPSED_HEIGHT = 22

local function _cloneDefault(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = _cloneDefault(val) end
    return out
end

local function _refreshHeightsForPage(parent)
    local list = _allSectionsOnPage[parent]
    if not list then return end
    -- Re-apply collapsed state now that children have been registered.
    -- (SetCollapsed runs during makeSection() with empty children, so any
    -- widgets registered afterwards stay visible until we hide them here.)
    for _, s in ipairs(list) do
        if s._collapsed then
            for _, w in ipairs(s.children) do if w.Hide then w:Hide() end end
            s.container:SetHeight(COLLAPSED_HEIGHT)
        elseif s.UpdateNaturalHeight then
            s:UpdateNaturalHeight()
        end
    end
end

-- Reparent a widget onto the section container, rebasing its anchor so it
-- moves with the container when sections above collapse/expand. Also stash
-- _homeContainer + _homeAnchors so the search-results page can move the
-- widget out and put it back when the search is cleared.
local function _captureAndReparent(widget, container, sectionOriginY)
    if not widget or not widget.GetPoint or not widget.SetPoint or not widget.SetParent then return end
    local nPoints = widget.GetNumPoints and widget:GetNumPoints() or 0
    if nPoints == 0 then return end
    local pageRoot = container:GetParent()
    local saved = {}
    for i = 1, nPoints do
        local p, relTo, relPoint, x, y = widget:GetPoint(i)
        saved[i] = { p = p, relTo = relTo, relPoint = relPoint, x = x or 0, y = y or 0 }
    end
    widget:SetParent(container)
    widget:ClearAllPoints()
    widget._homeContainer = container
    widget._homeAnchors   = {}

    -- Auto-flow: widgets originally placed in the right column (x >= 240 in
    -- the 700-wide reference layout) get re-anchored to the container's
    -- TOPRIGHT, preserving their original right-edge offset. As the panel
    -- resizes wider, col2 widgets follow the right edge instead of leaving
    -- a growing dead band in the middle.
    local COL2_THRESHOLD = 240
    local REFERENCE_W    = 700

    for i, a in ipairs(saved) do
        local newY  = a.y
        local relTo = a.relTo
        local newP, newRP, newX = a.p, a.relPoint, a.x
        if a.relTo == pageRoot or a.relTo == nil then
            relTo = container
            newY  = a.y - sectionOriginY
            -- Skip FontStrings/Textures: width is content-driven and re-anchoring
            -- against TOPRIGHT changes their visible position ambiguously,
            -- which breaks chained widgets anchored to them.
            local oType   = (widget.GetObjectType and widget:GetObjectType()) or ""
            local widgetW = (widget.GetWidth and widget:GetWidth()) or 0
            local isFrame = oType ~= "FontString" and oType ~= "Texture"
            if isFrame and a.x >= COL2_THRESHOLD and widgetW > 0 and a.p == "TOPLEFT" then
                local rightMargin = REFERENCE_W - (a.x + widgetW)
                if rightMargin < 4 then rightMargin = 4 end
                newP  = "TOPRIGHT"
                newRP = "TOPRIGHT"
                newX  = -rightMargin
            end
        end
        widget:SetPoint(newP, relTo, newRP, newX, newY)
        widget._homeAnchors[i] = { p = newP, relTo = relTo, relPoint = newRP, x = newX, y = newY }
    end
end

local function _registerInSection(w)
    if _currentSection and w then
        _captureAndReparent(w, _currentSection.container, _currentSection._originalY)
        w._homeSection = _currentSection
        _currentSection.children[#_currentSection.children + 1] = w
        -- If the section was restored as collapsed BEFORE any children
        -- were registered, newcomers would otherwise stay visible and
        -- bleed over the next section. Hide them on registration.
        if _currentSection._collapsed and w.Hide then w:Hide() end
    end
end

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
    sl._label = label

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
    sl._searchText  = label or ""
    sl._searchGroup = { sl }
    _registerInSection(sl); return sl
end

local function makeCheck(parent, label, key, x, y)
    local cb = CreateFrame("CheckButton", "TWOpt_"..key, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    cb:SetSize(24, 24)
    cb.Text:SetFontObject("GameFontHighlight")
    cb.Text:SetText(label)
    cb.dbKey = key
    cb._label = label
    cb:SetScript("OnClick", function(self)
        TW:GetDB()[key] = self:GetChecked() and true or false
        refresh()
    end)
    cb._searchText  = label or ""
    cb._searchGroup = { cb }
    _registerInSection(cb); return cb
end

local function makeDropdown(parent, label, key, options, x, y, width)
    -- Dropdown body is the anchor parent (so col2 auto-flow works), label
    -- sits ABOVE it — visual position identical to the old layout where the
    -- label was parent.
    local dd = CreateFrame("DropdownButton", "TWOpt_DD_"..key, parent, "WowStyle1DropdownTemplate")
    dd:SetWidth(width or 160)
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
    dd.dbKey = key
    dd._options = options
    dd._label = label

    local labelFS = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelFS:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 0, 2)
    labelFS:SetText(label)

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
    -- Searchable: collect option texts so the search bar can match them
    local optTexts = {}
    for _, o in ipairs(options) do optTexts[#optTexts + 1] = o.text end
    dd._optionTexts = table.concat(optTexts, " ")
    dd._searchText  = (label or "") .. " " .. dd._optionTexts
    dd._searchGroup = { dd, labelFS }
    _registerInSection(dd)
    _registerInSection(labelFS); return dd
end

local POPUP_ITEM_H = 22
local POPUP_VISIBLE = 12

local function makeMediaDropdown(parent, label, key, mediaType, x, y, width)
    width = width or 180

    -- btn (dropdown body) is the anchor parent so col2 auto-flow works;
    -- the label sits above it.
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, 24)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 18)

    local labelFS = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelFS:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 4)
    labelFS:SetText(label)
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
    btn._searchText  = label or ""
    btn._searchGroup = { btn, labelFS, previewBg, previewBorder, (previewTex or previewText) }
    _registerInSection(btn)
    _registerInSection(labelFS)
    _registerInSection(previewBg)
    _registerInSection(previewBorder)
    if previewTex  then _registerInSection(previewTex)  end
    if previewText then _registerInSection(previewText) end
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

    btn._searchText  = label or ""
    btn._searchGroup = lab and { lab, btn } or { btn }
    if lab then _registerInSection(lab) end
    _registerInSection(btn)
    return btn
end

-- Container-based section: a Frame chained TOPLEFT→prev.BOTTOMLEFT.
-- Widgets get reparented onto sec.container; collapsing shrinks the container,
-- everything below slides up automatically.
local function makeSection(parent, title, x, y)
    local section = {
        children   = {},
        title      = title,
        _searchText = (title or ""):lower(),
        _originalY = y,
        _parent    = parent,
    }

    local container = CreateFrame("Frame", nil, parent)
    local prev = _lastSectionOnPage[parent]
    if prev then
        container:SetPoint("TOPLEFT",  prev.container, "BOTTOMLEFT", 0, -SECTION_GAP)
        container:SetPoint("TOPRIGHT", parent,         "TOPRIGHT",   0,  0)
    else
        container:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, y)
        container:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    end
    container:SetHeight(COLLAPSED_HEIGHT)
    section.container = container
    _lastSectionOnPage[parent] = section
    _allSectionsOnPage[parent] = _allSectionsOnPage[parent] or {}
    _allSectionsOnPage[parent][#_allSectionsOnPage[parent] + 1] = section

    -- Header inside container at (x, 0)
    local header = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", container, "TOPLEFT", x, 0)
    header:SetTextColor(1, 0.82, 0)
    header:SetText(title)
    section.header = header
    parent._sectionHeaders = parent._sectionHeaders or {}
    parent._sectionHeaders[#parent._sectionHeaders + 1] = { title = title, region = header }

    -- Plus/Minus chevron next to header. Texture (not Button) so clicks
    -- pass through to the clickArea covering the whole bar.
    local chevron = container:CreateTexture(nil, "OVERLAY")
    chevron:SetSize(14, 14)
    chevron:SetPoint("LEFT", header, "RIGHT", 4, -1)
    section.chevron = chevron

    -- Invisible click strip covering the entire header row (title + separator
    -- line) so clicking anywhere on the bar toggles the section. Excludes
    -- the chevron at the left and the reset button on the right so those
    -- still get their own clicks.
    local clickArea = CreateFrame("Button", nil, container)
    clickArea:SetPoint("TOPLEFT",  container, "TOPLEFT",  x - 14, -2)
    clickArea:SetPoint("TOPRIGHT", container, "TOPRIGHT", -40,    -2)
    clickArea:SetHeight(18)
    clickArea:RegisterForClicks("LeftButtonUp")
    -- Make sure the strip sits above the header texture / line so clicks
    -- on the bar always hit it. Sibling buttons (fold chevron, reset btn)
    -- get explicit higher levels so they keep their own clicks.
    clickArea:SetFrameLevel((container:GetFrameLevel() or 0) + 1)
    section.clickArea = clickArea

    local TEX_EXPANDED  = "Interface\\Buttons\\UI-MinusButton-Up"
    local TEX_COLLAPSED = "Interface\\Buttons\\UI-PlusButton-Up"
    chevron:SetTexture(TEX_EXPANDED)

    -- Reset button (refresh icon at the far right of the section row)
    local btnReset = CreateFrame("Button", nil, container)
    btnReset:SetSize(14, 14)
    btnReset:SetPoint("TOPRIGHT", container, "TOPRIGHT", -14, -1)
    btnReset:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    btnReset:GetNormalTexture():SetTexCoord(0.05, 0.95, 0.05, 0.95)
    btnReset:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    btnReset:SetFrameLevel((container:GetFrameLevel() or 0) + 5)
    btnReset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L["Reset this section to default values."] or
            "Reset this section to default values.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btnReset:SetScript("OnLeave", GameTooltip_Hide)
    section.btnReset = btnReset

    -- Gold separator line, anchored inside the container
    local line = container:CreateTexture(nil, "OVERLAY")
    line:SetHeight(1)
    line:SetColorTexture(1, 0.82, 0, 0.55)
    section.line = line
    local function placeLine()
        local hw = header:GetStringWidth() or 0
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT",  container, "TOPLEFT",  x + hw + 4 + 14 + 8, -7)
        line:SetPoint("TOPRIGHT", container, "TOPRIGHT", -42, -7)
    end
    placeLine()
    C_Timer.After(0, placeLine)

    function section:UpdateNaturalHeight()
        if self._collapsed then
            self.container:SetHeight(COLLAPSED_HEIGHT)
            return
        end
        local cTop = self.container:GetTop()
        if not cTop then
            C_Timer.After(0, function() self:UpdateNaturalHeight() end)
            return
        end
        local lowest, gotAnyChildPos = cTop, false
        for _, w in ipairs(self.children) do
            if w.IsShown and w:IsShown() and w.GetBottom then
                local b = w:GetBottom()
                if b then
                    gotAnyChildPos = true
                    if b < lowest then lowest = b end
                end
            end
        end
        -- If we have children but none have a resolved bottom yet, defer.
        -- Otherwise the container shrinks to COLLAPSED_HEIGHT, the next section
        -- anchors right under it and you get a stack of overlapping rows.
        if not gotAnyChildPos and #self.children > 0 then
            C_Timer.After(0, function() self:UpdateNaturalHeight() end)
            return
        end
        local span = math.max(COLLAPSED_HEIGHT, cTop - lowest + 8)
        self.container:SetHeight(span)
    end

    function section:SetCollapsed(state, persist)
        state = state and true or false
        for _, w in ipairs(self.children) do
            if state then if w.Hide then w:Hide() end
            else            if w.Show then w:Show() end end
        end
        line:SetShown(not state)
        chevron:SetTexture(state and TEX_COLLAPSED or TEX_EXPANDED)
        header:SetTextColor(state and 0.7 or 1, state and 0.6 or 0.82, state and 0.2 or 0)
        self._collapsed = state
        if state then
            self.container:SetHeight(COLLAPSED_HEIGHT)
        else
            self:UpdateNaturalHeight()
        end
        if persist then
            TankWatchDB = TankWatchDB or {}
            TankWatchDB.collapsedSections = TankWatchDB.collapsedSections or {}
            TankWatchDB.collapsedSections[title] = state or nil
        end
    end

    function section:Toggle() self:SetCollapsed(not self._collapsed, true) end

    function section:ResetToDefaults()
        local db = TW:GetDB()
        for _, w in ipairs(self.children) do
            if w.dbKey and TW.Defaults and TW.Defaults[w.dbKey] ~= nil then
                db[w.dbKey] = _cloneDefault(TW.Defaults[w.dbKey])
            end
        end
        if TW.RefreshAll then TW:RefreshAll() end
        if TW.ApplyFonts  then TW:ApplyFonts()  end
        if panel and panel.refreshAll then panel.refreshAll() end
    end

    clickArea:SetScript("OnClick", function() section:Toggle() end)
    clickArea:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L["Click to collapse/expand this section."] or
            "Click to collapse/expand this section.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    clickArea:SetScript("OnLeave", GameTooltip_Hide)
    btnReset:SetScript("OnClick", function() section:ResetToDefaults() end)

    -- Restore prior collapsed state from DB (key = title, simple and stable enough)
    TankWatchDB = TankWatchDB or {}
    local restored = TankWatchDB.collapsedSections and TankWatchDB.collapsedSections[title]
    section:SetCollapsed(restored or false, false)

    -- Subsequent makeXxx() / _registerInSection() calls attach to this section.
    _currentSection = section
    return section
end

-- Hover tooltip helper. Hooks the widget AND known sub-controls of composite widgets.
-- Also appends a "Default: X" line if the widget has a dbKey with a default in TW.Defaults.
-- Stores `text` on widget._tooltip so the search bar can match it too.
local function addTooltip(widget, text)
    if not widget or not text or text == "" then return widget end
    widget._tooltip = text
    -- Index for the search bar: append the tooltip body so users can search by
    -- description, not just label. Lower-cased once at build time.
    widget._searchText = ((widget._searchText or "") .. " " .. text):lower()
    local function defaultStr(self)
        local key = self.dbKey
        if not key or not TW.Defaults or TW.Defaults[key] == nil then return nil end
        local d = TW.Defaults[key]
        local t = type(d)
        if t == "boolean" then return d and "ON" or "OFF"
        elseif t == "number" then return tostring(d)
        elseif t == "string" then return d
        end
        return nil
    end
    local function show(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(text, 1, 1, 1, true)
        local owner = self
        -- Bubble up to find the actual dbKey-bearing widget (for slider sub-controls)
        while owner and not owner.dbKey do owner = owner.GetParent and owner:GetParent() end
        if owner then
            local d = defaultStr(owner)
            if d then GameTooltip:AddLine((L["Default: "] or "Default: ") .. d, 0.6, 0.6, 0.6) end
        end
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
    -- Layout/anchor is handled by layoutTabs() at panel build time and on
    -- OnSizeChanged so the tab strip wraps onto multiple rows when the
    -- panel is too narrow to fit them all in a single row.
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

local function buildBarsPage(page)
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
end

local function buildTextPage(page)
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

    _registerInSection(header)
    _registerInSection(frame)
    _registerInSection(addLabel)
    _registerInSection(edit)
    _registerInSection(addBtn)
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

    _registerInSection(header)
    _registerInSection(frame)
    _registerInSection(addLabel)
    _registerInSection(edit)
    _registerInSection(addBtn)
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
        OnShow   = function(self) self.EditBox:SetText(""); self.EditBox:SetFocus() end,
        OnAccept = function(self) if self.data and self.data.onAccept then self.data.onAccept(self.EditBox:GetText()) end end,
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
            local function doImport(overwrite)
                local ok, err = TW:ImportProfile(name, raw, overwrite)
                if ok then
                    TW:SetActiveProfile(name)
                    profileDropdownRefresh()
                    refreshExport()
                    if panel and panel.refreshAll then panel.refreshAll() end
                    print("|cff00ff96TankWatch:|r " .. format(L["profile '%s' imported"], name))
                elseif err == "exists" then
                    askConfirm(format(L["Profile '%s' already exists. Overwrite?"], name), function()
                        doImport(true)
                    end)
                else
                    print("|cff00ff96TankWatch:|r " .. L["import failed:"] .. " " .. tostring(err))
                end
            end
            doImport(false)
        end)
    end)
    addTooltip(btnImport, L["Decode the export string and create a new profile from it."])

    -- ============ PRESETS ============
    -- Applying a preset creates a NEW profile (clone of current + preset
    -- overrides) and switches to it. Original profile is preserved.
    local presetHeader = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    presetHeader:SetPoint("TOPLEFT", btnImport, "BOTTOMLEFT", 0, -18)
    presetHeader:SetText(L["Presets"])
    presetHeader:SetTextColor(1, 0.82, 0)

    local presetLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    presetLabel:SetPoint("TOPLEFT", presetHeader, "BOTTOMLEFT", 0, -6)
    presetLabel:SetText(L["Apply preset (creates a new profile, original preserved)"])

    local presetDD = CreateFrame("DropdownButton", "TWOpt_DD_preset", page, "WowStyle1DropdownTemplate")
    presetDD:SetPoint("TOPLEFT", presetLabel, "BOTTOMLEFT", 0, -4)
    presetDD:SetWidth(280)

    local presetChoice = "FULL"
    local PRESET_LIST = {
        { value = "FULL",          text = L["Full — bars + auras (default)"] },
        { value = "COMPACT_AURAS", text = L["Compact — class icon + auras only"] },
        { value = "AURAS_ONLY",    text = L["Minimal — auras only (no class icon)"] },
    }
    presetDD:SetupMenu(function(_, root)
        for _, p in ipairs(PRESET_LIST) do
            root:CreateRadio(p.text,
                function() return presetChoice == p.value end,
                function() presetChoice = p.value end)
        end
    end)
    presetDD:GenerateMenu()
    addTooltip(markAsNew(presetDD, "v1.3_presets"),
        L["Pre-configured display modes. Applying creates a new profile copying your current one with the preset's display settings overlaid — your filters, position, fonts and colors are preserved."])

    local btnApplyPreset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    btnApplyPreset:SetSize(120, 22)
    btnApplyPreset:SetPoint("LEFT", presetDD, "RIGHT", 8, 0)
    btnApplyPreset:SetText(L["Apply"])
    btnApplyPreset:SetScript("OnClick", function()
        local presetText = "?"
        for _, p in ipairs(PRESET_LIST) do
            if p.value == presetChoice then presetText = p.text break end
        end
        local current = TW:GetActiveProfileName()
        local suggested = current .. " - " .. presetText:match("^([^—]+)") or current
        suggested = suggested:gsub("%s+$", "")
        askName(format(L["New profile name (will copy '%s' and apply the preset):"], current), function(name)
            name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" then return end
            local ok, err = TW:ApplyPresetAsNewProfile(presetChoice, name)
            if ok then
                profileDropdownRefresh()
                if panel and panel.refreshAll then panel.refreshAll() end
                print("|cff00ff96TankWatch:|r " .. format(L["preset applied as new profile '%s'"], name))
            else
                print("|cff00ff96TankWatch:|r " .. tostring(err))
            end
        end)
    end)
    addTooltip(btnApplyPreset, L["Apply the selected preset by creating a new profile."])

    page._refreshProfiles = function()
        profileDropdownRefresh()
        refreshExport()
        charLabel:SetText(L["Character:"] .. " |cffffffff" .. TW:GetCharKey() .. "|r")
    end
end

-- ============================================================
-- CHANGELOG PAGE — renders CHANGELOG-like content from an embedded
-- string. Versions in gold, bullets in white. Scrollable.
-- ============================================================
local CHANGELOG_TEXT = L["CHANGELOG_BODY"] or [[
## v1.4.6

|cffffd700New|r — SplitWatch added to the sister-tab switcher
- A SplitWatch side tab now appears on the left edge alongside the
  BossWatch tab when SplitWatch is installed — one click swaps to its
  options panel at the same position.

|cffffd700Improved|r — Changelog moved into About tab
- One less tab in the strip: the changelog now lives as a collapsible
  section at the bottom of the About tab (SplitWatch convention).
- Same content, folds away by default to keep the meta info compact.

## v1.4.5

|cffffd700Fixed|r — Off-screen frame on lower resolutions
- If the saved container position lands entirely outside the viewport
  (e.g. dragged on a 4K screen, now playing on 1080p), the frame is
  auto-repositioned to the default LEFT 50,0 on next layout pass with
  a chat notice.

## v1.4.4

|cffffd700New|r — Tooltips on debuff icons
- Hover over any debuff to see the standard Blizzard tooltip with the
  full description (secret-safe via SetUnitDebuff).
- Test-mode icons show a stub tooltip so you can preview placement.

|cffffd700Improved|r — Boss debuff coverage
- The "Boss-cast only" filter now tries every Blizzard HARMFUL filter
  (RAID, RAID_IN_COMBAT, IMPORTANT, DISPELLABLE, RAID_PLAYER_DISPELLABLE)
  before falling back. M+/dungeon debuffs that were tagged IMPORTANT
  but not RAID now show up.

## v1.4.3

|cffffd700Fixed|r — Boss debuffs no longer missing on retail
- The "Boss-cast only" filter now uses Blizzard's secret-safe RAID
  filter — picks up encounter debuffs that were filtered out before
  because their `isBossAura` field was secret-tagged.
- Class icon in compact mode now reads the English class token from
  UnitClass (was reading the localized name → CLASS_ICON_COORDS lookup
  failed → whole texture sheet was visible).
- Changing visibility mode hides/shows frames immediately (no /reload).

## v1.4.2

|cffffd700New|r — Slash command renamed: /tankw (with /tankwatch alias)
- /tw was too short and risked colliding with other addons; same
  convention as BossWatch's /bossw and SplitWatch's /splitw.

|cffffd700New|r — Multi-row tab strip
- When the panel is too narrow to fit every tab in one row, the strip
  wraps onto multiple rows. Bottom rows render above the rows above
  so tab top edges aren't clipped.

|cffffd700New|r — MoP Classic 5.5 support
- TankWatch now runs on Mists of Pandaria Classic via a separate TOC
  (Interface 50500). One CurseForge zip ships both retail and Classic.
- C_UnitAuras isn't available on Classic, so debuff scanning falls back
  to the legacy UnitAura API — boss-cast debuff display works the same
  on both clients.
- C_AddOns.GetAddOnMetadata / IsAddOnLoaded fall back to the legacy
  globals so the version label and the BossWatch/SplitWatch sister
  tabs work too.

## v1.4.1

|cffffd700New|r — Sister-addon side tabs
- Discreet tabs on the left edge of the options panel let you switch
  between TankWatch and its watch-family sister addons (BossWatch,
  SplitWatch) with one click.
- A sister tab only appears when its addon is also installed.
- Modern style: dark glass backdrop, gold accent stripe on the active
  addon, glow on hover.

## v1.4.0

|cffffd700New|r — Modern responsive options panel
- Resize grip in the bottom-right; size and position saved account-wide.
- Right-click the grip to reset the panel to its default 720×620 size.
- Per-tab scroll memory: each tab remembers its scroll offset.
- Subtle fade-in when switching tabs; footer shows active profile + tank count.

|cffffd700New|r — Collapsible sections
- Every section now has a collapse/expand chevron AND the whole header bar
  (title + gold separator) is clickable to toggle.
- Per-section reset button (refresh icon, far right) restores defaults
  for that section's controls only — your other settings stay untouched.
- Collapsed state is persisted across reloads.

|cffffd700New|r — Search bar (top-right)
- Type any keyword from a label or tooltip; matching widgets are gathered
  on a results page with a breadcrumb pointing back to their tab/section.
- Tab labels show a hit count when a search is active.
- Clearing the search restores everything to its home tab.

|cffffd700New|r — Auto-flow layout
- Right-column widgets (dropdowns, sliders) now follow the right edge
  when you widen the panel, instead of leaving a growing dead band.

|cffffd700New|r — Changelog tab
- This very tab! Per-version blocks with a localized label
  (Nouveautés / Neuerungen / Novedades / Novità / Novidades / Что нового /
  변경 사항 / 更新日志 / 更新日誌).

|cffffd700Improved|r
- Section + collapse strings translated across 9 languages.
- Test buttons chained together so they stay grouped at any panel width.
- Wider "Off" button so its text doesn't bleed into the "1" button.
- Cleaner section spacing (28px between containers).

## v1.3.0

|cffffd700New|r — Compact mode (now default for fresh installs)
- Class icon + boss-cast debuffs only. HP/power/absorb/name all hidden.
- Toggle in Layout > General. Sub-option to hide the class icon (auras only).

|cffffd700New|r — Display presets (Profiles tab)
- Full / Compact / Minimal preset dropdown.
- Non-destructive: clones your current profile, overlays preset display flags.

|cffffd700New|r — Power bar
- Optional rage / mana / runic / energy / fury / pain bar below HP.
- Auto-colored by power type or custom color, LSM texture.

|cffffd700Improved|r — Test mode
- HP and absorbs animate, debuff durations cycle, stacks change live,
  power bars tick at different rates per power type.

|cffffd700Fixed|r
- Removed unreliable HP/power format dropdowns (12.0 secret-value issues).
- HP/name text always render above the absorb shield overlay.
- Mover handle floats above tank frames so it can be dragged.

## v1.2.2

- Reorganized options panel: Range Fade in Layout, merged Health-bar
  texture/color, merged Aura Size+Layout into Icons, panel-opacity moved
  to About > Options window.
- 552 new translations across 8 languages (deDE/esES/itIT/ptBR/ruRU/koKR/zhCN/zhTW).
- Tooltips also appear on slider sub-controls (steppers, thumb).

## v1.2.1

- Discord invite link added in the About tab.

## v1.2.0

|cffffd700New|r — Absorb shield
- Translucent shield bar overlaid on the HP bar (Death Strike, WoG, etc.).
- Sky-blue by default, fully customizable, LSM texture, side-flip.

|cffffd700Improved|r
- Mover handle floats above tank frames.
- Tighter spacing on Bars tab (no overlap between texture preview and side dropdown).

|cffffd700Fixed|r
- Removed Percent / Current+Percent HP formats — unreliable on group members in 12.0.

|cffffd700Packaging|r
- All bundled libs (LibStub, CallbackHandler, LibSharedMedia, LibDataBroker)
  now show in CurseForge "Embedded Libraries" with correct versions.

## v1.1.5

- Profile import overwrite-confirmation dialog translated in 9 languages.

## v1.1.4

- Importing a profile with an existing name now asks
  "Profile 'X' already exists. Overwrite?".

## v1.1.3

- Fixed the green portrait placeholder on some setups (logo now shows correctly).

## v1.1.2

- logo.png shipped in the package so the portrait icon shows from CurseForge.

## v1.1.1

- Fixed crash on the profile-name dialog (New / Import).

## v1.1.0

|cffffd700New|r — Modern options panel
- Redesigned with Blizzard's modern panel template.
- ESC closes the panel.
- Adjustable panel opacity, full tooltips on every control.
- Gold section dividers, smooth scrolling on long pages.
- CurseForge and Wago.io links in About.

## v1.0.4

- Auto-shows in Titan Panel / ChocolateBar via LibDataBroker launcher.
- "NEW" badge on freshly added options (clears on first hover/click).
- 8 new locale stubs (deDE/esES/itIT/ptBR/ruRU/koKR/zhCN/zhTW).

## v1.0.3

- Released on Wago.io alongside CurseForge.

## v1.0.2

- Background customization (color/texture, custom or class color, alpha).
- Right-click while moving locks the position.

## v1.0.1

- Fixed a critical issue that could prevent clicking on bag items while
  TankWatch was loaded.
- Mover overlay matches actual visible content size.

## v1.0.0

- First public release on CurseForge.
- Tank detection (raid role / /maintank / 5-man / solo).
- Boss-cast debuff icons with the |cffffd700stack count rendered HUGE in the
  icon center|r — the headline feature.
- Whitelist / blacklist by spell ID (great for M+ trash debuffs).
- Per-character profiles with export / import.
]]

local function buildAboutPage(page)
    local meta = TW.GetAddOnMetadata
    local version = (meta and meta(addonName, "Version")) or "?"
    local author  = (meta and meta(addonName, "Author"))  or "Timikana"

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

    -- Classic-build notice (only shown on non-retail clients)
    if WOW_PROJECT_ID and WOW_PROJECT_ID ~= (WOW_PROJECT_MAINLINE or 1) then
        local notice = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        notice:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -10)
        notice:SetWidth(380); notice:SetJustifyH("LEFT")
        notice:SetTextColor(1, 0.6, 0)
        notice:SetText("|cffff9900⚠ " ..
            (L["Classic build — UI not fully tested. Report issues on GitHub / Discord."]
             or "Classic build — UI not fully tested. Report issues on GitHub / Discord.") .. "|r")
    end

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
    urlField(-370, "|cff5865f2" .. L["Discord (support / bugs / suggestions):"] .. "|r", "https://discord.gg/uFmxwexQ4P")

    -- Panel opacity slider (account-wide; lives on About since it's a meta-setting
    -- about the options window itself, not the tank frames).
    local alphaHeader = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    alphaHeader:SetPoint("TOPLEFT", 14, -425)
    alphaHeader:SetText(L["Options window"])
    alphaHeader:SetTextColor(1, 0.82, 0)

    local alphaSlider = CreateFrame("Frame", nil, page, "MinimalSliderWithSteppersTemplate")
    alphaSlider:SetWidth(280)
    alphaSlider:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -445)
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

    local cmdHeader = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cmdHeader:SetPoint("TOPLEFT", 14, -510)
    cmdHeader:SetText(L["Slash commands"])
    cmdHeader:SetTextColor(1, 0.82, 0)

    local cmds = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cmds:SetPoint("TOPLEFT", cmdHeader, "BOTTOMLEFT", 0, -6)
    cmds:SetWidth(560); cmds:SetJustifyH("LEFT"); cmds:SetSpacing(3)
    cmds:SetText(
        "|cffffff00/tankw|r — " .. L["open options"] .. "\n" ..
        "|cffffff00/tankw config|r |cff888888(" .. L["alias"] .. ")|r — " .. L["open options"] .. "\n" ..
        "|cffffff00/tankw options|r |cff888888(" .. L["alias"] .. ")|r — " .. L["open options"] .. "\n" ..
        "|cffffff00/tankw mover|r — " .. L["toggle mover"] .. "\n" ..
        "|cffffff00/tankw test N|r — " .. L["simulate N tanks (0-8)"] .. "\n" ..
        "|cffffff00/tankw reset|r — " .. L["reset all settings + reload"] .. "\n" ..
        "|cffffff00/tankw debug|r — " .. L["print roster role/maintank info"] .. "\n" ..
        "|cffffff00/tankw auradebug|r — " .. L["print every HARMFUL aura on each tank unit"] .. "\n" ..
        "|cffffff00/tankwatch|r — " .. L["long alias for /tankw"]
    )

    local hint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 14, 12)
    hint:SetText(L["Click a URL to select it, then Ctrl+C to copy."])

    -- ----------------------------------------------------------------
    -- Changelog section, chained at the bottom (SplitWatch convention:
    -- About + Changelog live in the same tab). Anchored well below the
    -- slash-commands list (which ends ~y=-660 with 9 lines).
    -- ----------------------------------------------------------------
    makeSection(page, L["Changelog"], 14, -680)
    local entries = {}
    local cur
    for raw in (CHANGELOG_TEXT .. "\n"):gmatch("([^\n]*)\n") do
        local v = raw:match("^##%s*(.+)$")
        if v then
            cur = { ver = v, lines = {} }
            entries[#entries + 1] = cur
        elseif cur then
            local bullet = raw:match("^%-%s+(.+)$")
            if bullet then
                cur.lines[#cur.lines + 1] = { kind = "bullet", text = bullet }
            elseif raw:match("^%s*$") then
                -- skip blanks
            elseif raw:match("^%s%s") then
                local last = cur.lines[#cur.lines]
                if last then last.text = last.text .. " " .. raw:gsub("^%s+", "") end
            else
                cur.lines[#cur.lines + 1] = { kind = "subhead", text = raw }
            end
        end
    end

    local y = -710
    for _, entry in ipairs(entries) do
        local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 14, y)
        title:SetText("|cffeda14a" .. entry.ver .. "|r")
        _registerInSection(title)
        y = y - 24

        for _, line in ipairs(entry.lines) do
            local fs
            if line.kind == "subhead" then
                fs = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                fs:SetPoint("TOPLEFT", 18, y)
                fs:SetWidth(660)
                fs:SetJustifyH("LEFT")
                fs:SetSpacing(2)
                fs:SetText(line.text)
                _registerInSection(fs)
                local rows = math.max(1, math.ceil(#line.text / 100))
                y = y - (rows * 16 + 4)
            else
                fs = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                fs:SetPoint("TOPLEFT", 28, y)
                fs:SetWidth(640)
                fs:SetJustifyH("LEFT")
                fs:SetSpacing(2)
                fs:SetText("• " .. line.text)
                _registerInSection(fs)
                local rows = math.max(1, math.ceil(#line.text / 95))
                y = y - (rows * 16 + 4)
            end
        end
        y = y - 14
    end

    local ghHint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ghHint:SetPoint("TOPLEFT", 14, y - 6)
    ghHint:SetText(L["Full GitHub history: https://github.com/Timikana/TankWatch/releases"]
        or "Full GitHub history: https://github.com/Timikana/TankWatch/releases")
    _registerInSection(ghHint)
end

-- ============================================================
-- BUILD
-- ============================================================

local function build()
    panel = CreateFrame("Frame", "TankWatchOptions", UIParent, "PortraitFrameTemplate")
    panel:SetSize(720, 620)
    panel:SetPoint("CENTER")
    panel:SetMovable(true); panel:EnableMouse(true)
    panel:SetResizable(true)
    if panel.SetResizeBounds then
        panel:SetResizeBounds(720, 500, 1400, 1100)
    elseif panel.SetMinResize then
        panel:SetMinResize(620, 480)
        panel:SetMaxResize(1200, 900)
    end
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        TankWatchDB = TankWatchDB or {}
        TankWatchDB.panelPos = {
            point  = "TOPLEFT",
            relTo  = "UIParent",
            relPt  = "BOTTOMLEFT",
            x      = self:GetLeft() or 0,
            y      = self:GetTop()  or 0,
        }
    end)
    panel:SetFrameStrata("HIGH")
    panel:Hide()
    panel:SetClampedToScreen(true)

    -- Restore saved size + position (account-wide)
    TankWatchDB = TankWatchDB or {}
    if TankWatchDB.panelSize and TankWatchDB.panelSize.w and TankWatchDB.panelSize.h then
        panel:SetSize(TankWatchDB.panelSize.w, TankWatchDB.panelSize.h)
    end
    if TankWatchDB.panelPos and TankWatchDB.panelPos.x and TankWatchDB.panelPos.y then
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            TankWatchDB.panelPos.x, TankWatchDB.panelPos.y)
    end

    -- Close on ESC
    tinsert(UISpecialFrames, "TankWatchOptions")

    if panel.SetTitle then panel:SetTitle(L["TankWatch — Options"]) end
    -- SetPortraitToAsset silently fails for non-square / non-standard PNGs in 12.0,
    -- leaving a green placeholder. Set the texture directly on the portrait region.
    if panel.PortraitContainer and panel.PortraitContainer.portrait then
        panel.PortraitContainer.portrait:SetTexture("Interface\\AddOns\\TankWatch\\logo.png")
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
        content:SetSize(sf:GetWidth() > 0 and sf:GetWidth() or 680, 900)
        sf:SetScrollChild(content)
        sf.content = content
        -- Content width must follow the scroll viewport so section reset
        -- buttons (anchored to container TOPRIGHT) don't disappear off the
        -- right edge when the user shrinks the panel.
        sf:SetScript("OnSizeChanged", function(self, w, _)
            if w and w > 0 and self.content then self.content:SetWidth(w) end
        end)
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

    -- Each buildXxxPage starts with _currentSection = nil so widgets created
    -- before the first makeSection don't get tagged with a stale section.
    local function buildPage(name, fn)
        local sf = newPage(name); _currentSection = nil
        fn(sf.content)
        -- Recompute every section's natural height once anchors resolve.
        C_Timer.After(0, function() _refreshHeightsForPage(sf.content) end)
        autoFitPage(sf); return sf
    end
    pages.layout   = buildPage("layout",   buildLayoutPage)
    pages.bars     = buildPage("bars",     buildBarsPage)
    pages.text     = buildPage("text",     buildTextPage)
    pages.auras    = buildPage("auras",    buildAurasPage)
    pages.filters  = buildPage("filters",  buildFiltersPage)
    pages.profiles = buildPage("profiles", buildProfilesPage)
    pages.about    = buildPage("about",    buildAboutPage)
    _currentSection = nil

    -- ========================================================
    -- Hidden "search results" page — not in the tab list. When the search
    -- box has a query, every matching widget group is reparented here on
    -- the fly with a breadcrumb pointing back to its real tab/section.
    -- ========================================================
    local resultsPage = newPage("results")
    local resultsContent = resultsPage.content
    pages._results = resultsPage

    local breadcrumbPool = {}
    local activeMatches = {}
    local lastNormalTabId = "layout"

    local function _moveGroupToResults(w, y)
        if not w._searchGroup then return y end
        for _, comp in ipairs(w._searchGroup) do
            if comp and comp.SetParent then
                comp:SetParent(resultsContent)
                if comp.Show then comp:Show() end
            end
        end
        local leader = w._searchGroup[1]
        if leader and leader.ClearAllPoints then
            leader:ClearAllPoints()
            leader:SetPoint("TOPLEFT", resultsContent, "TOPLEFT", 14, y)
        end
        return y - 64
    end

    local function _restoreGroupHome(w)
        if not w._searchGroup then return end
        for _, comp in ipairs(w._searchGroup) do
            if comp and comp._homeContainer and comp.SetParent then
                comp:SetParent(comp._homeContainer)
            end
            if comp and comp._homeAnchors and comp.ClearAllPoints then
                comp:ClearAllPoints()
                for _, a in ipairs(comp._homeAnchors) do
                    comp:SetPoint(a.p, a.relTo, a.relPoint, a.x, a.y)
                end
            end
        end
    end

    local function _gatherMatches(query)
        local matches = {}
        for _, sections in pairs(_allSectionsOnPage) do
            for _, section in ipairs(sections) do
                for _, w in ipairs(section.children) do
                    local txt = w._searchText
                    if txt and w._searchGroup and txt:lower():find(query, 1, true) then
                        matches[#matches + 1] = w
                    end
                end
            end
        end
        return matches
    end

    _searchImpl = function(rawQuery)
        local q = (rawQuery or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local empty = (q == "")

        -- Always restore prior results state first
        for _, w in ipairs(activeMatches) do _restoreGroupHome(w) end
        wipe(activeMatches)
        for _, fs in ipairs(breadcrumbPool) do fs:Hide() end

        if empty then
            resultsPage:Hide()
            for _, p in pairs(pages) do
                if p ~= resultsPage then p:Hide() end
            end
            if pages[lastNormalTabId] then pages[lastNormalTabId]:Show() end
            for _, ref in ipairs(_searchTabRefs) do
                ref.btn:SetText(ref.label)
                if PanelTemplates_TabResize then PanelTemplates_TabResize(ref.btn, 0) end
            end
            return
        end

        local matches = _gatherMatches(q)

        for _, p in pairs(pages) do
            if p ~= resultsPage then p:Hide() end
        end

        local hitsByPage = {}
        local y = -10
        for i, w in ipairs(matches) do
            local fs = breadcrumbPool[i]
            if not fs then
                fs = resultsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                breadcrumbPool[i] = fs
            end
            fs:Show()
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", resultsContent, "TOPLEFT", 14, y)
            local section = w._homeSection
            local sectionTitle = (section and section.header and section.header:GetText()) or "?"
            local pageContent = section and section._parent
            local tabLabel = "?"
            for _, ref in ipairs(_searchTabRefs) do
                if ref.content == pageContent then tabLabel = ref.label; break end
            end
            fs:SetText("|cff888888" .. tabLabel .. "  >  " .. sectionTitle .. "|r")

            if pageContent then hitsByPage[pageContent] = (hitsByPage[pageContent] or 0) + 1 end

            y = y - 14
            y = _moveGroupToResults(w, y)
            activeMatches[#activeMatches + 1] = w
        end

        if #matches == 0 then
            local fs = breadcrumbPool[1]
            if not fs then
                fs = resultsContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                breadcrumbPool[1] = fs
            end
            fs:Show()
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", resultsContent, "TOPLEFT", 14, -20)
            fs:SetText(L["No options match your search."] or "No options match your search.")
        end

        resultsContent:SetHeight(math.max(resultsPage:GetHeight(), math.abs(y) + 24))
        resultsPage:Show()

        for _, ref in ipairs(_searchTabRefs) do
            local n = hitsByPage[ref.content] or 0
            if n == 0 then
                ref.btn:SetText(ref.label)
            else
                ref.btn:SetText(ref.label .. " |cffeda14a(" .. n .. ")|r")
            end
            if PanelTemplates_TabResize then PanelTemplates_TabResize(ref.btn, 0) end
        end
    end

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
    local _savedScroll = {}     -- scroll offset memorized per tab
    local _currentTabId = nil
    local function selectTab(id)
        -- If a search is active, clear it first (which restores reparented widgets)
        if searchBox and searchBox:GetText() ~= "" then
            searchBox:SetText("")
        end
        lastNormalTabId = id
        -- Save current tab's scroll position before switching
        if _currentTabId and pages[_currentTabId] and pages[_currentTabId].GetVerticalScroll then
            _savedScroll[_currentTabId] = pages[_currentTabId]:GetVerticalScroll()
        end
        for _, p in pairs(pages) do p:Hide() end
        if pages[id] then
            local target = pages[id]
            target:Show()
            -- Restore scroll for this tab (deferred to next frame after content shows)
            if target.SetVerticalScroll then
                local saved = _savedScroll[id] or 0
                C_Timer.After(0, function() target:SetVerticalScroll(saved) end)
            end
            -- Fade-in animation (quick, subtle)
            target:SetAlpha(0)
            local ag = target.fadeIn
            if not ag then
                ag = target:CreateAnimationGroup()
                local a = ag:CreateAnimation("Alpha")
                a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.18); a:SetSmoothing("OUT")
                target.fadeIn = ag
                ag:SetScript("OnFinished", function() target:SetAlpha(1) end)
            end
            ag:Stop(); ag:Play()
        end
        for _, t in ipairs(tabBtns) do
            styleTabSelected(t, t.id == id)
        end
        _currentTabId = id
    end

    wipe(_searchTabRefs)
    for i, t in ipairs(tabs) do
        local b = makeTab(panel, t.id, t.label, tabBtns[i - 1])
        b:SetScript("OnClick", function() selectTab(t.id) end)
        tabBtns[#tabBtns + 1] = b
        if pages[t.id] and pages[t.id].content then
            _searchTabRefs[#_searchTabRefs + 1] = {
                btn = b, content = pages[t.id].content, label = t.label,
            }
        end
    end

    -- Wrap tabs onto multiple rows when the panel is too narrow.
    -- Bottom rows get a higher FrameLevel so their top edges don't get
    -- clipped under the row above (PanelTabButtonTemplate's top edge sits
    -- a few pixels above its anchor y, which would render under the next
    -- row otherwise — looks ugly).
    local function layoutTabs()
        local available = panel:GetWidth() - 24
        local x, y = 12, 2
        local rowH = 24
        local row = 0
        local baseLevel = panel:GetFrameLevel()
        for _, tab in ipairs(tabBtns) do
            local w = tab:GetWidth()
            if x > 12 and (x + w) > available + 12 then
                x = 12
                y = y - rowH
                row = row + 1
            end
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", x, y)
            tab:SetFrameLevel(baseLevel + 2 + row * 2)
            x = x + w + 2
        end
    end
    layoutTabs()
    panel:HookScript("OnSizeChanged", layoutTabs)

    -- ========================================================
    -- Resize grip (bottom-right). Saves the chosen size in
    -- TankWatchDB.panelSize, restored next time the panel is opened.
    -- pageHolder + ScrollFrames are anchored to TOPLEFT/BOTTOMRIGHT so
    -- they follow the resize automatically. autoFitPage is re-run on
    -- stop so the scrollbars hide/show appropriately at the new height.
    -- ========================================================
    local resizeGrip = CreateFrame("Button", nil, panel)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:SetFrameLevel(panel:GetFrameLevel() + 10)
    resizeGrip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L["Drag to resize"], 1, 1, 1)
        GameTooltip:AddLine(L["Right-click to reset size"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    resizeGrip:SetScript("OnLeave", GameTooltip_Hide)
    resizeGrip:RegisterForClicks("LeftButtonDown", "RightButtonUp")
    resizeGrip:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then panel:StartSizing("BOTTOMRIGHT") end
    end)
    resizeGrip:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            panel:StopMovingOrSizing()
            TankWatchDB = TankWatchDB or {}
            TankWatchDB.panelSize = { w = panel:GetWidth(), h = panel:GetHeight() }
            for _, sf in pairs(pages) do autoFitPage(sf) end
        elseif button == "RightButton" then
            -- Reset to default size
            panel:SetSize(720, 620)
            TankWatchDB = TankWatchDB or {}
            TankWatchDB.panelSize = nil
            for _, sf in pairs(pages) do autoFitPage(sf) end
            GameTooltip:Hide()
        end
    end)

    -- ========================================================
    -- Search bar (top-right) — port of BossWatch's results-page approach.
    -- Matches widgets by `_searchText` (label + tooltip body, indexed at
    -- build time) and reparents the matching `_searchGroup` onto a hidden
    -- "results" page with a breadcrumb pointing back to the home tab/section.
    -- Clearing the search restores every group to its `_homeContainer`.
    -- ========================================================
    local searchBox = CreateFrame("EditBox", "TWOpt_Search", panel, "InputBoxTemplate")
    searchBox:SetSize(200, 22)
    searchBox:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -38, -32)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(40)
    searchBox:SetFontObject("GameFontHighlight")
    searchBox:SetTextInsets(20, 18, 0, 0)

    local searchIcon = searchBox:CreateTexture(nil, "OVERLAY")
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("LEFT", searchBox, "LEFT", 4, 0)

    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    searchPlaceholder:SetPoint("LEFT", searchIcon, "RIGHT", 4, 0)
    searchPlaceholder:SetText(L["Search options…"] or "Search options…")

    local searchClear = CreateFrame("Button", nil, searchBox)
    searchClear:SetSize(16, 16)
    searchClear:SetPoint("RIGHT", searchBox, "RIGHT", -2, 0)
    searchClear:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    searchClear:Hide()

    local function runSearch(text)
        searchPlaceholder:SetShown(text == "")
        searchClear:SetShown(text ~= "")
        _applySearch(text)
    end
    searchBox:SetScript("OnTextChanged",   function(self) runSearch(self:GetText()) end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    searchClear:SetScript("OnClick",       function() searchBox:SetText(""); searchBox:ClearFocus() end)
    addTooltip(searchBox, L["Filter the panel: type any keyword from a label or tooltip. Sections without a match are auto-collapsed."]
        or "Filter the panel: type any keyword from a label or tooltip.")
    addTooltip(searchClear, L["Clear the search."] or "Clear the search.")

    -- ========================================================
    -- Footer status bar — shows active profile, visible tank count
    -- ========================================================
    local footer = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 4)
    footer:SetJustifyH("LEFT")

    local function refreshFooter()
        local profile = TW.GetActiveProfileName and TW:GetActiveProfileName() or "?"
        local nTanks = 0
        if TW.TankFrames then
            for i = 1, (TW.MAX_TANKS or 8) do
                local f = TW.TankFrames[i]
                if f and (f._unit or f._testMode) then nTanks = nTanks + 1 end
            end
        end
        local lock = InCombatLockdown() and "  |cffff5555[combat]|r" or ""
        footer:SetFormattedText("|cffaaaaaa%s:|r |cffffffff%s|r   |cffaaaaaa•|r   %d %s%s",
            L["Profile"] or "Profile", profile, nTanks, L["tanks"] or "tanks", lock)
    end
    refreshFooter()

    -- Refresh footer periodically (every 1s) so combat / tank count stay live
    local footerTicker = C_Timer and C_Timer.NewTicker and C_Timer.NewTicker(1, refreshFooter)
    panel:HookScript("OnHide", function() if footerTicker then footerTicker:Cancel(); footerTicker = nil end end)
    panel:HookScript("OnShow", function()
        if not footerTicker then footerTicker = C_Timer.NewTicker(1, refreshFooter) end
        refreshFooter()
    end)

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

    -- =====================================================================
    -- Sister-addon side tabs (left edge of the panel, modern style). Self
    -- (TankWatch) on top, sister (BossWatch) below if its addon is loaded.
    -- Click → close this panel + open the other addon's options.
    -- =====================================================================
    local SIDE_TAB_SIZE = 48
    local sideTabs = {
        { id = "TankWatch",  isSelf = true,  icon = "Interface\\AddOns\\TankWatch\\Media\\icon",
          tooltip = L["TankWatch — Options"], onClick = function() end },
        { id = "BossWatch",  isSelf = false, icon = "Interface\\AddOns\\BossWatch\\Media\\logo.png",
          tooltip = L["Open BossWatch options"] or "Open BossWatch options",
          loadedCheck = function()
              local BW = _G.BossWatch
              return TW.IsAddOnLoaded and TW.IsAddOnLoaded("BossWatch")
                     and BW and BW.ToggleOptions
          end,
          onClick = function()
              local point, _, relPoint, x, y
              if panel and panel:IsShown() then
                  point, _, relPoint, x, y = panel:GetPoint(1)
                  panel:Hide()
              end
              local BW = _G.BossWatch
              if BW and BW.ShowOptionsAt and point then
                  BW:ShowOptionsAt(point, relPoint, x, y)
              elseif BW and BW.ToggleOptions then
                  BW:ToggleOptions()
              end
          end },
        { id = "SplitWatch", isSelf = false, icon = "Interface\\AddOns\\SplitWatch\\Media\\logo.png",
          tooltip = L["Open SplitWatch options"] or "Open SplitWatch options",
          loadedCheck = function()
              local SW = _G.SplitWatch
              return TW.IsAddOnLoaded and TW.IsAddOnLoaded("SplitWatch")
                     and SW and SW.ToggleOptions
          end,
          onClick = function()
              local point, _, relPoint, x, y
              if panel and panel:IsShown() then
                  point, _, relPoint, x, y = panel:GetPoint(1)
                  panel:Hide()
              end
              local SW = _G.SplitWatch
              if SW and SW.ShowOptionsAt and point then
                  SW:ShowOptionsAt(point, relPoint, x, y)
              elseif SW and SW.ToggleOptions then
                  SW:ToggleOptions()
              end
          end },
    }

    local visibleIdx = 0
    for _, def in ipairs(sideTabs) do
        if def.isSelf or (def.loadedCheck and def.loadedCheck()) then
            visibleIdx = visibleIdx + 1

            local tab = CreateFrame("Button", nil, panel, "BackdropTemplate")
            tab:SetSize(SIDE_TAB_SIZE, SIDE_TAB_SIZE)
            tab:SetPoint("TOPLEFT", panel, "TOPLEFT", -SIDE_TAB_SIZE + 8,
                         -68 - (visibleIdx - 1) * (SIDE_TAB_SIZE + 8))
            tab:SetFrameLevel(panel:GetFrameLevel() + 5)

            tab:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            tab:SetBackdropColor(0.04, 0.04, 0.07, 0.95)

            local sheen = tab:CreateTexture(nil, "ARTWORK")
            sheen:SetPoint("TOPLEFT",     tab, "TOPLEFT",      1, -1)
            sheen:SetPoint("BOTTOMRIGHT", tab, "TOPRIGHT",    -1, -math.floor(SIDE_TAB_SIZE * 0.45))
            sheen:SetColorTexture(1, 1, 1, 1)
            if sheen.SetGradient and CreateColor then
                sheen:SetGradient("VERTICAL",
                    CreateColor(1, 1, 1, 0.10),
                    CreateColor(1, 1, 1, 0.00))
            else
                sheen:SetVertexColor(1, 1, 1, 0.06)
            end

            local shade = tab:CreateTexture(nil, "ARTWORK")
            shade:SetPoint("BOTTOMLEFT",  tab, "BOTTOMLEFT",   1,  1)
            shade:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -1,  1)
            shade:SetHeight(math.floor(SIDE_TAB_SIZE * 0.40))
            shade:SetColorTexture(0, 0, 0, 1)
            if shade.SetGradient and CreateColor then
                shade:SetGradient("VERTICAL",
                    CreateColor(0, 0, 0, 0.00),
                    CreateColor(0, 0, 0, 0.45))
            else
                shade:SetVertexColor(0, 0, 0, 0.20)
            end

            local icon = tab:CreateTexture(nil, "ARTWORK", nil, 2)
            icon:SetPoint("CENTER", tab, "CENTER", 0, 0)
            icon:SetSize(SIDE_TAB_SIZE - 14, SIDE_TAB_SIZE - 14)
            icon:SetTexture(def.icon)
            icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)

            local function makeEdge(point1, point2, w, h)
                local t = tab:CreateTexture(nil, "BORDER")
                t:SetPoint(point1, tab, point1, 0, 0)
                t:SetPoint(point2, tab, point2, 0, 0)
                if w then t:SetWidth(w) end
                if h then t:SetHeight(h) end
                return t
            end
            local edges = {
                makeEdge("TOPLEFT", "TOPRIGHT", nil, 1),
                makeEdge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1),
                makeEdge("TOPLEFT", "BOTTOMLEFT", 1, nil),
                makeEdge("TOPRIGHT", "BOTTOMRIGHT", 1, nil),
            }
            local function setEdgeColor(r, g, b, a)
                for _, t in ipairs(edges) do t:SetColorTexture(r, g, b, a) end
            end
            setEdgeColor(0.20, 0.20, 0.24, 1)

            local glow = tab:CreateTexture(nil, "OVERLAY")
            glow:SetPoint("TOPLEFT",     tab, "TOPLEFT",     -10,  10)
            glow:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT",  10, -10)
            glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
            glow:SetBlendMode("ADD")
            glow:SetVertexColor(1, 0.82, 0, 0.85)
            glow:Hide()

            local marker = tab:CreateTexture(nil, "OVERLAY", nil, 1)
            marker:SetPoint("TOPRIGHT",    tab, "TOPRIGHT",    -0.5, -3)
            marker:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -0.5,  3)
            marker:SetWidth(3)
            marker:SetColorTexture(1, 0.82, 0, 1)
            marker:Hide()

            if def.isSelf then
                setEdgeColor(1, 0.82, 0, 1)
                glow:Show()
                marker:Show()
                tab:EnableMouse(false)
            else
                tab:HookScript("OnEnter", function()
                    setEdgeColor(1, 0.82, 0, 1)
                    glow:Show()
                end)
                tab:HookScript("OnLeave", function()
                    setEdgeColor(0.20, 0.20, 0.24, 1)
                    glow:Hide()
                end)
                tab:SetScript("OnClick", def.onClick)
            end

            addTooltip(tab, def.tooltip)
        end
    end
end

function TW:ToggleOptions()
    if not panel then build() end
    if panel:IsShown() then panel:Hide()
    else panel.refreshAll(); panel:Show() end
end

-- Cross-addon handoff: open the panel at a specific position, used by sister
-- addons (BossWatch) when switching via side tabs so the window doesn't jump
-- to its previously-saved spot. Coordinates are persisted, so reopening later
-- from the minimap / slash command will land in the same place.
function TW:ShowOptionsAt(point, relPoint, x, y)
    if not panel then build() end
    if point then
        panel:ClearAllPoints()
        panel:SetPoint(point, UIParent, relPoint or point, x or 0, y or 0)
        TankWatchDB.panelPoint = {
            point = point, relPoint = relPoint or point,
            x = math.floor((x or 0) + 0.5),
            y = math.floor((y or 0) + 0.5),
        }
    end
    panel.refreshAll()
    panel:Show()
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

    local version = (TW.GetAddOnMetadata and TW.GetAddOnMetadata(addonName, "Version")) or "?"
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
    hint:SetText(L["You can also use the slash command: /tankw"])

    local category = Settings.RegisterCanvasLayoutCategory(host, "TankWatch")
    category.ID = "TankWatch"
    Settings.RegisterAddOnCategory(category)
    TW._settingsCategoryID = category:GetID()
end
