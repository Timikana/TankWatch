local addonName, TW = ...
local L = TW.L

local CreateFrame = CreateFrame
local pairs, ipairs = pairs, ipairs

local panel
local refresh = function() if TW.RefreshAll then TW:RefreshAll() end end

-- ============================================================
-- WIDGET FACTORIES (same patterns as BossWatch)
-- ============================================================

local function makeSlider(parent, label, key, minV, maxV, step, x, y, width)
    local sl = CreateFrame("Slider", "TWOpt_"..key, parent, "OptionsSliderTemplate")
    sl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    sl:SetWidth(width or 180)
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(step)
    sl:SetObeyStepOnDrag(true)
    _G[sl:GetName().."Low"]:SetText(""); _G[sl:GetName().."High"]:SetText("")
    _G[sl:GetName().."Text"]:SetText(label)

    local edit = CreateFrame("EditBox", nil, sl, "InputBoxTemplate")
    edit:SetSize(46, 18)
    edit:SetPoint("LEFT", sl, "RIGHT", 8, 0)
    edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlightSmall")
    sl.edit = edit
    sl.dbKey = key

    sl:SetScript("OnValueChanged", function(self, val)
        if step < 1 then val = math.floor(val * 100 + 0.5) / 100
        else val = math.floor(val + 0.5) end
        TW:GetDB()[key] = val
        edit:SetText(tostring(val))
        refresh()
    end)
    edit:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v then sl:SetValue(v) end
        self:ClearFocus()
    end)
    return sl
end

local function makeCheck(parent, label, key, x, y)
    local cb = CreateFrame("CheckButton", "TWOpt_"..key, parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
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

    local dd = CreateFrame("Frame", "TWOpt_DD_"..key, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", -18, -2)
    UIDropDownMenu_SetWidth(dd, width or 130)
    dd.dbKey = key

    local function setSelected(val, text)
        TW:GetDB()[key] = val
        UIDropDownMenu_SetText(dd, text)
        refresh()
    end

    UIDropDownMenu_Initialize(dd, function()
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text
            info.value = opt.value
            info.func = function() setSelected(opt.value, opt.text) end
            info.checked = (TW:GetDB()[key] == opt.value)
            UIDropDownMenu_AddButton(info)
        end
    end)
    dd.refresh = function()
        local cur = TW:GetDB()[key]
        for _, opt in ipairs(options) do
            if opt.value == cur then UIDropDownMenu_SetText(dd, opt.text); return end
        end
    end
    return dd
end

-- ============================================================
-- CUSTOM MEDIA DROPDOWN (scrollable popup with previews)
-- ============================================================
local POPUP_ITEM_H = 22
local POPUP_VISIBLE = 12

local function makeMediaDropdown(parent, label, key, mediaType, x, y, width)
    width = width or 180

    local labelFS = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelFS:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    labelFS:SetText(label)

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, 22)
    btn:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -4)
    btn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.08, 0.08, 0.10, 1)
    btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    btn.dbKey = key

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btnText:SetPoint("LEFT", btn, "LEFT", 6, 0)
    btnText:SetPoint("RIGHT", btn, "RIGHT", -16, 0)
    btnText:SetJustifyH("LEFT")

    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(14, 14)
    arrow:SetPoint("RIGHT", btn, "RIGHT", -2, 0)

    -- External preview
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

    -- Scrollable popup
    local popupW = width + 40
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetSize(popupW, POPUP_ITEM_H * POPUP_VISIBLE + 12)
    popup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    popup:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
    popup:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
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
-- TABS
-- ============================================================
local function makeTab(parent, id, label, idx)
    local tab = CreateFrame("Button", "TWTab"..id, parent, "BackdropTemplate")
    tab:SetSize(72, 22)
    tab:SetPoint("TOPLEFT", parent, "TOPLEFT", 8 + (idx - 1) * 76, -28)
    tab:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    tab:SetBackdropColor(0.12, 0.12, 0.14, 1)
    tab:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetText(label)
    tab.text = text
    tab.id = id
    return tab
end

-- ============================================================
-- PAGES
-- ============================================================

local function buildLayoutPage(page)
    local y = -10
    local btnMover = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    btnMover:SetSize(160, 22); btnMover:SetPoint("TOPLEFT", 14, y)
    btnMover:SetText(L["Unlock / Lock Mover"])
    btnMover:SetScript("OnClick", function() TW:ToggleMover() end)

    local label = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 184, y - 4)
    label:SetText(L["Test:"])

    local function currentTestCount()
        local n = 0
        for i = 1, TW.MAX_TANKS do
            if TW.TankFrames[i] and TW.TankFrames[i]._testMode then n = n + 1 end
        end
        return n
    end

    local testBtns = {}
    local function refreshTestBtns()
        local n = currentTestCount()
        for i, b in ipairs(testBtns) do
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
        b:SetScript("OnClick", function()
            TW:SetTestMode(count)
            refreshTestBtns()
        end)
        testBtns[#testBtns + 1] = b
        xs = xs + 36
    end
    refreshTestBtns()

    y = y - 30
    makeCheck(page, L["Enable"], "enabled", 14, y)

    -- Minimap button toggle (lives in global DB, not the active profile)
    local mmCB = CreateFrame("CheckButton", "TWOpt_minimap", page, "InterfaceOptionsCheckButtonTemplate")
    mmCB:SetPoint("TOPLEFT", page, "TOPLEFT", 184, y)
    mmCB.Text:SetText(L["Show minimap button"])
    mmCB:SetScript("OnShow", function(self)
        local g = TW:GetGlobalDB()
        self:SetChecked(not (g.minimap and g.minimap.hide))
    end)
    mmCB:SetScript("OnClick", function(self)
        local g = TW:GetGlobalDB()
        g.minimap = g.minimap or {}
        g.minimap.hide = not self:GetChecked()
        if TW.UpdateMinimapButton then TW:UpdateMinimapButton() end
    end)

    y = y - 26
    makeDropdown(page, L["Anchor"], "anchor", ANCHOR9(), 14, y)
    makeDropdown(page, L["Grow Direction"], "growDirection", {
        { text = L["Down"], value = "DOWN" }, { text = L["Up"], value = "UP" },
    }, 184, y)
    y = y - 50
    makeSlider(page, L["Offset X"], "anchorX", -1500, 1500, 1, 14, y)
    makeSlider(page, L["Offset Y"], "anchorY", -1500, 1500, 1, 260, y)
    y = y - 50
    makeSlider(page, L["Width"],  "frameWidth",  100, 400, 1, 14, y)
    makeSlider(page, L["Height"], "frameHeight",  20, 100, 1, 260, y)
    y = y - 50
    makeSlider(page, L["Spacing"], "frameSpacing", 0, 40, 1, 14, y)
    makeSlider(page, L["Scale"],   "frameScale",  0.5, 2.0, 0.05, 260, y)
end

local function buildBarsPage(page)
    local y = -10
    makeMediaDropdown(page, L["Health Texture"], "healthTexture", "statusbar", 14, y, 180)
    y = y - 50
    makeDropdown(page, L["Health Color"], "healthColorMode", {
        { text = L["Class color"],     value = "CLASS" },
        { text = L["Reaction (green)"], value = "REACTION" },
        { text = L["Custom static"],   value = "STATIC" },
    }, 14, y, 180)
    y = y - 50
    makeSlider(page, L["HP background alpha"], "healthBackgroundAlpha", 0, 1, 0.05, 14, y)
end

local function buildTextPage(page)
    local y = -10
    makeCheck(page, L["Show Name"], "showName", 14, y)
    makeDropdown(page, L["Name Position"], "nameAnchor", ANCHOR9(), 184, y)
    y = y - 50
    makeSlider(page, L["Name Offset X"], "nameX", -80, 80, 1, 14, y)
    makeSlider(page, L["Name Offset Y"], "nameY", -80, 80, 1, 260, y)
    y = y - 50
    makeSlider(page, L["Name max length (0=off)"], "nameMaxLength", 0, 30, 1, 14, y, 250)
    y = y - 40
    makeCheck(page, L["Show Health Text"], "showHealthText", 14, y)
    makeDropdown(page, L["HP text position"], "healthTextAnchor", ANCHOR9(), 184, y)
    y = y - 50
    makeSlider(page, L["HP text Offset X"], "healthTextX", -80, 80, 1, 14, y)
    makeSlider(page, L["HP text Offset Y"], "healthTextY", -80, 80, 1, 260, y)
    y = y - 50
    makeDropdown(page, L["HP format"], "healthTextFormat", {
        { text = L["Percent (50%)"],    value = "PERCENT" },
        { text = L["Current (50M)"],     value = "CURRENT" },
        { text = L["Current + Percent"], value = "CURRENT_PERCENT" },
        { text = L["Current / Max"],     value = "CURRENT_MAX" },
    }, 14, y, 200)

    y = y - 60
    local fontHeader = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontHeader:SetPoint("TOPLEFT", 14, y)
    fontHeader:SetText(L["Font (applies to all text)"])
    y = y - 18
    makeMediaDropdown(page, L["Font"], "fontFace", "font", 14, y, 180)
    y = y - 50
    makeSlider(page, L["Font Size"], "fontSize", 8, 24, 1, 14, y)
    makeDropdown(page, L["Outline"], "fontOutline", {
        { text = L["None"],          value = "NONE" },
        { text = L["Outline"],       value = "OUTLINE" },
        { text = L["Thick Outline"], value = "THICKOUTLINE" },
    }, 260, y)
end

local function buildAurasPage(page)
    local y = -10
    makeCheck(page, L["Show Auras"], "showAuras", 14, y)
    makeCheck(page, L["Only debuffs with stacks"], "aurasOnlyStacks", 184, y)
    y = y - 30
    local note = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 14, y)
    note:SetWidth(520); note:SetJustifyH("LEFT")
    note:SetText(L["Only boss-cast HARMFUL auras are shown. The stack count is rendered big in the icon center."])
    y = y - 30
    makeSlider(page, L["Max Count"], "aurasMaxCount", 1, 10, 1, 14, y)
    makeSlider(page, L["Size"], "aurasSize", 16, 64, 1, 260, y)
    y = y - 50
    makeSlider(page, L["Spacing"], "aurasSpacing", 0, 12, 1, 14, y)
    y = y - 50
    makeDropdown(page, L["Anchor"], "aurasAnchor", ANCHOR9(), 14, y)
    makeDropdown(page, L["Grow X"], "aurasGrowX", {
        { text = L["Left"],  value = "LEFT" },
        { text = L["Right"], value = "RIGHT" },
    }, 260, y)
    y = y - 50
    makeSlider(page, L["Offset X"], "aurasX", -200, 200, 1, 14, y)
    makeSlider(page, L["Offset Y"], "aurasY", -200, 200, 1, 260, y)
end

-- ============================================================
-- POPUP: name input (used by New / Copy)
-- ============================================================
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["TANKWATCH_PROFILE_NAME"] = {
    text         = "%s",
    button1      = OKAY or "OK",
    button2      = CANCEL or "Cancel",
    hasEditBox   = true,
    editBoxWidth = 240,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnShow       = function(self) self.editBox:SetText(""); self.editBox:SetFocus() end,
    OnAccept     = function(self) if self.data and self.data.onAccept then self.data.onAccept(self.editBox:GetText()) end end,
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
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnAccept     = function(self) if self.data and self.data.onAccept then self.data.onAccept() end end,
}

local function askName(prompt, onAccept)
    local d = StaticPopup_Show("TANKWATCH_PROFILE_NAME", prompt)
    if d then d.data = { onAccept = onAccept } end
end

local function askConfirm(prompt, onAccept)
    local d = StaticPopup_Show("TANKWATCH_CONFIRM", prompt)
    if d then d.data = { onAccept = onAccept } end
end

-- ============================================================
-- PROFILES PAGE
-- ============================================================
local function buildProfilesPage(page)
    local y = -10

    -- Active profile dropdown (custom — refreshes from TW:ListProfiles)
    local labelFS = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelFS:SetPoint("TOPLEFT", 14, y)
    labelFS:SetText(L["Active profile"])

    local dd = CreateFrame("Frame", "TWOpt_DD_profile", page, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", -18, -2)
    UIDropDownMenu_SetWidth(dd, 200)

    local function refreshDD()
        UIDropDownMenu_SetText(dd, TW:GetActiveProfileName())
    end
    UIDropDownMenu_Initialize(dd, function()
        for _, name in ipairs(TW:ListProfiles()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = name
            info.value   = name
            info.checked = (name == TW:GetActiveProfileName())
            info.func    = function()
                TW:SetActiveProfile(name)
                refreshDD()
                if panel and panel.refreshAll then panel.refreshAll() end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    dd.refresh = refreshDD
    refreshDD()

    -- Char info
    local charFS = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    charFS:SetPoint("TOPLEFT", 240, y - 20)
    charFS:SetText(L["Character:"] .. " |cffffffff" .. TW:GetCharKey() .. "|r")

    y = y - 64

    -- Action buttons
    local function mkBtn(text, x, yy, w, onClick)
        local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        b:SetSize(w or 110, 22)
        b:SetPoint("TOPLEFT", x, yy)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end

    mkBtn(L["New..."], 14, y, 110, function()
        askName(L["Name of the new profile (copies current settings):"], function(name)
            local ok, err = TW:CreateProfile(name, TW:GetActiveProfileName())
            if ok then
                TW:SetActiveProfile(name)
                refreshDD()
                if panel and panel.refreshAll then panel.refreshAll() end
                print("|cff00ff96TankWatch:|r " .. format(L["profile '%s' created"], name))
            else
                print("|cff00ff96TankWatch:|r " .. tostring(err))
            end
        end)
    end)

    mkBtn(L["Reset"], 134, y, 110, function()
        askConfirm(format(L["Reset profile '%s' to defaults?"], TW:GetActiveProfileName()), function()
            TW:ResetCurrentProfile()
            if panel and panel.refreshAll then panel.refreshAll() end
            if TW.RefreshAll then TW:RefreshAll() end
        end)
    end)

    mkBtn(L["Delete"], 254, y, 110, function()
        local cur = TW:GetActiveProfileName()
        if cur == "Default" then
            print("|cff00ff96TankWatch:|r " .. L["cannot delete Default"]); return
        end
        askConfirm(format(L["Delete profile '%s'?"], cur), function()
            TW:DeleteProfile(cur)
            TW:SetActiveProfile("Default")
            refreshDD()
            if panel and panel.refreshAll then panel.refreshAll() end
        end)
    end)

    y = y - 36

    -- Export
    local expHeader = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    expHeader:SetPoint("TOPLEFT", 14, y)
    expHeader:SetText(L["Export"])
    y = y - 18

    local expScroll = CreateFrame("ScrollFrame", "TWOpt_ExportScroll", page, "InputScrollFrameTemplate")
    expScroll:SetSize(520, 80)
    expScroll:SetPoint("TOPLEFT", 14, y)
    expScroll.EditBox:SetWidth(500)
    expScroll.EditBox:SetFontObject("ChatFontSmall")
    expScroll.EditBox:SetMaxLetters(0)
    expScroll.CharCount:Hide()
    if expScroll.EditBox.SetCountInvisibleLetters then expScroll.EditBox:SetCountInvisibleLetters(true) end

    local function refreshExport()
        local s = TW:ExportProfile(TW:GetActiveProfileName()) or ""
        expScroll.EditBox:SetText(s)
        expScroll.EditBox:HighlightText(0, 0)
    end

    y = y - 86
    mkBtn(L["Refresh export"], 14, y, 140, refreshExport)
    mkBtn(L["Select all"], 158, y, 100, function()
        expScroll.EditBox:SetFocus()
        expScroll.EditBox:HighlightText()
    end)
    refreshExport()

    y = y - 30

    -- Import
    local impHeader = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    impHeader:SetPoint("TOPLEFT", 14, y)
    impHeader:SetText(L["Import"])
    y = y - 18

    local impScroll = CreateFrame("ScrollFrame", "TWOpt_ImportScroll", page, "InputScrollFrameTemplate")
    impScroll:SetSize(520, 80)
    impScroll:SetPoint("TOPLEFT", 14, y)
    impScroll.EditBox:SetWidth(500)
    impScroll.EditBox:SetFontObject("ChatFontSmall")
    impScroll.EditBox:SetMaxLetters(0)
    impScroll.CharCount:Hide()
    if impScroll.EditBox.SetCountInvisibleLetters then impScroll.EditBox:SetCountInvisibleLetters(true) end

    y = y - 86
    mkBtn(L["Import as new profile..."], 14, y, 200, function()
        local raw = impScroll.EditBox:GetText()
        if not raw or raw == "" then
            print("|cff00ff96TankWatch:|r " .. L["import box is empty"]); return
        end
        askName(L["Name for the imported profile:"], function(name)
            local ok, err = TW:ImportProfile(name, raw)
            if ok then
                TW:SetActiveProfile(name)
                refreshDD()
                refreshExport()
                if panel and panel.refreshAll then panel.refreshAll() end
                print("|cff00ff96TankWatch:|r " .. format(L["profile '%s' imported"], name))
            else
                print("|cff00ff96TankWatch:|r " .. L["import failed:"] .. " " .. tostring(err))
            end
        end)
    end)

    page._refreshProfiles = function()
        refreshDD()
        refreshExport()
        charFS:SetText(L["Character:"] .. " |cffffffff" .. TW:GetCharKey() .. "|r")
    end
end

local function buildAboutPage(page)
    local version = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
    local author  = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Author")  or "Timikana"

    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetText("|cff00ff96TankWatch|r  v" .. version)

    local sub = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetWidth(520); sub:SetJustifyH("LEFT")
    sub:SetText(L["See every tank in your group with their boss-cast debuffs and stack counts."])

    local byLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    byLabel:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
    byLabel:SetText(L["Author:"] .. " |cffffffff" .. author .. "|r")

    local cmdHeader = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cmdHeader:SetPoint("TOPLEFT", 14, -120)
    cmdHeader:SetText(L["Slash commands"])

    local cmds = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cmds:SetPoint("TOPLEFT", cmdHeader, "BOTTOMLEFT", 0, -6)
    cmds:SetWidth(520); cmds:SetJustifyH("LEFT"); cmds:SetSpacing(3)
    cmds:SetText(
        "|cffffff00/tw|r — " .. L["open options"] .. "\n" ..
        "|cffffff00/tw mover|r — " .. L["toggle mover"] .. "\n" ..
        "|cffffff00/tw test N|r — " .. L["simulate N tanks (0-8)"] .. "\n" ..
        "|cffffff00/tw reset|r — " .. L["reset all settings + reload"]
    )
end

-- ============================================================
-- BUILD
-- ============================================================
local function build()
    panel = CreateFrame("Frame", "TankWatchOptions", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(560, 540)
    panel:SetPoint("CENTER")
    panel:SetMovable(true); panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetFrameStrata("HIGH")
    panel:Hide()
    panel.TitleText:SetText(L["TankWatch — Options"])

    local pageHolder = CreateFrame("Frame", nil, panel)
    pageHolder:SetPoint("TOPLEFT", 4, -56)
    pageHolder:SetPoint("BOTTOMRIGHT", -4, 4)

    local pages = {}
    local function newPage()
        local p = CreateFrame("Frame", nil, pageHolder)
        p:SetAllPoints(pageHolder)
        p:Hide()
        return p
    end

    pages.layout   = newPage(); buildLayoutPage(pages.layout)
    pages.bars     = newPage(); buildBarsPage(pages.bars)
    pages.text     = newPage(); buildTextPage(pages.text)
    pages.auras    = newPage(); buildAurasPage(pages.auras)
    pages.profiles = newPage(); buildProfilesPage(pages.profiles)
    pages.about    = newPage(); buildAboutPage(pages.about)

    local tabs = {
        { id = "layout",   label = L["Layout"] },
        { id = "bars",     label = L["Bars"] },
        { id = "text",     label = L["Text"] },
        { id = "auras",    label = L["Auras"] },
        { id = "profiles", label = L["Profiles"] },
        { id = "about",    label = L["About"] },
    }
    local tabBtns = {}
    local function selectTab(id)
        for _, p in pairs(pages) do p:Hide() end
        if pages[id] then pages[id]:Show() end
        for _, t in ipairs(tabBtns) do
            if t.id == id then
                t:SetBackdropColor(0.05, 0.18, 0.20, 1)
                t:SetBackdropBorderColor(0, 1, 0.6, 1)
                t.text:SetTextColor(0, 1, 0.6)
            else
                t:SetBackdropColor(0.12, 0.12, 0.14, 1)
                t:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                t.text:SetTextColor(0.8, 0.8, 0.8)
            end
        end
    end

    for i, t in ipairs(tabs) do
        local b = makeTab(panel, t.id, t.label, i)
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
                    elseif child.SetValue and child.edit then
                        child:SetValue(db[child.dbKey] or 0)
                        child.edit:SetText(tostring(db[child.dbKey] or 0))
                    elseif child.refresh then
                        child:refresh()
                    end
                end
                walk(child)
            end
        end
        walk(pageHolder)
        if pages.profiles and pages.profiles._refreshProfiles then
            pages.profiles._refreshProfiles()
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
