-- Options/Widgets.lua — widget factories (addTooltip, markAsNew,
-- makeSlider, makeCheck, makeDropdown, makeMediaDropdown,
-- makeColorPicker, makeSpellList, makeNameList, ANCHOR9).
--
-- Loaded AFTER Options/Panel.lua, BEFORE Options/Pages/*.lua. Panel.lua
-- owns the section system (_registerInSection + container chaining);
-- factories here grab it via TW._OptHelpers.registerInSection at file
-- top and register themselves onto the same table for the page modules
-- to consume.
local addonName, TW = ...
local L = TW.L
local format = string.format

local h = TW._OptHelpers
local _registerInSection = h.registerInSection

-- Shared "redraw all" callback used by every factory that mutates the DB.
local function refresh()
    if TW.RefreshAll then TW:RefreshAll() end
end

-- ============================================================
-- markAsNew
-- ============================================================
h.markAsNew = function(widget, key)
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


-- ============================================================
-- makeSlider
-- ============================================================
h.makeSlider = function(parent, label, key, minV, maxV, step, x, y, width)
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


-- ============================================================
-- makeCheck
-- ============================================================
h.makeCheck = function(parent, label, key, x, y)
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


-- ============================================================
-- makeDropdown
-- ============================================================
h.makeDropdown = function(parent, label, key, options, x, y, width)
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


-- ============================================================
-- makeMediaDropdown
-- ============================================================
local POPUP_ITEM_H = 22
local POPUP_VISIBLE = 12

h.makeMediaDropdown = function(parent, label, key, mediaType, x, y, width)
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


-- ============================================================
-- makeColorPicker
-- ============================================================
h.makeColorPicker = function(parent, label, dbKey, x, y)
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

-- ============================================================
-- addTooltip
-- ============================================================
h.addTooltip = function(widget, text)
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


-- ============================================================
-- ANCHOR9
-- ============================================================
h.ANCHOR9 = function()
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
-- Spell-name lookup + spell/name lists used by the Filters page
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
h.makeSpellList = function(parent, dbKey, title, x, y, w, h)
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

h.makeNameList = function(parent, dbKey, title, x, y, w, h)
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

-- Late-bound exports (defined further down the file than the initial
-- _OptHelpers literal). Page modules read these at first call, which is
-- always after the whole Panel.lua chunk has finished loading.
