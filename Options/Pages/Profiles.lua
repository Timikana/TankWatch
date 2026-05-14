local addonName, TW = ...
local L = TW.L
local format = string.format

local h = TW._OptHelpers
local addTooltip       = h.addTooltip
local markAsNew        = h.markAsNew

TW.OptPages = TW.OptPages or {}

function TW.OptPages.buildProfiles(page)
    local askName     = h.askName
    local askConfirm  = h.askConfirm
    local profileDropdownRefresh
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
                    if TW._OptPanel and TW._OptPanel.refreshAll then TW._OptPanel.refreshAll() end
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
                if TW._OptPanel and TW._OptPanel.refreshAll then TW._OptPanel.refreshAll() end
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
            if TW._OptPanel and TW._OptPanel.refreshAll then TW._OptPanel.refreshAll() end
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
            if TW._OptPanel and TW._OptPanel.refreshAll then TW._OptPanel.refreshAll() end
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
                    if TW._OptPanel and TW._OptPanel.refreshAll then TW._OptPanel.refreshAll() end
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
                if TW._OptPanel and TW._OptPanel.refreshAll then TW._OptPanel.refreshAll() end
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
