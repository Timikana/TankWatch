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
-- SECTION CONTAINER
-- Section header + chevron + click-strip + reset button. Widgets
-- registered via _registerInSection get reparented onto the container
-- so collapsing it pulls everything below up via the chain.
-- ============================================================
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

-- ============================================================
-- HELPER NAMESPACE
-- Panel.lua exposes the section system here. Widget factories
-- (Options/Widgets.lua) populate the rest at load time. Page modules
-- (Options/Pages/*.lua) read the whole table at file top.
-- ============================================================
TW._OptHelpers = TW._OptHelpers or {}
TW._OptHelpers.registerInSection = _registerInSection
TW._OptHelpers.makeSection       = makeSection
TW.OptPages = TW.OptPages or {}

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

-- Late-bound popup helpers — used by Options/Pages/Profiles.lua.
TW._OptHelpers.askName      = askName
TW._OptHelpers.askConfirm   = askConfirm
TW._OptHelpers.ensurePopups = ensurePopups

local function build()
    -- Factories live in Options/Widgets.lua now; pull what build() itself
    -- still calls (just addTooltip for the search box + side tabs).
    local addTooltip = TW._OptHelpers.addTooltip

    panel = CreateFrame("Frame", "TankWatchOptions", UIParent, "PortraitFrameTemplate")
    TW._OptPanel = panel   -- exposed for split page modules (Options/Pages/*.lua)
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

    -- Restore saved size + position (account-wide). Clamp the size to the
    -- current screen so a window saved on a larger monitor doesn't end up
    -- bigger than the viewport. Off-screen rescue happens on first Show.
    TankWatchDB = TankWatchDB or {}
    if TankWatchDB.panelSize and TankWatchDB.panelSize.w and TankWatchDB.panelSize.h then
        local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
        local sw = math.min(TankWatchDB.panelSize.w, math.max(720, pw - 40))
        local sh = math.min(TankWatchDB.panelSize.h, math.max(500, ph - 40))
        panel:SetSize(sw, sh)
    end
    if TankWatchDB.panelPos and TankWatchDB.panelPos.x and TankWatchDB.panelPos.y then
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            TankWatchDB.panelPos.x, TankWatchDB.panelPos.y)
    end

    -- Off-screen rescue: when the panel is shown, if it lands entirely
    -- outside the viewport (saved on a larger resolution, now on a
    -- smaller one), reset to centered + default size.
    panel:HookScript("OnShow", function(self)
        C_Timer.After(0, function()
            if not self.GetLeft then return end
            local l, r  = self:GetLeft(),   self:GetRight()
            local bt, t = self:GetBottom(), self:GetTop()
            local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
            if not (l and r and bt and t and pw and ph) then return end
            local off = (r < 20) or (l > pw - 20) or (t < 20) or (bt > ph - 20)
            if off then
                TankWatchDB.panelPos  = nil
                TankWatchDB.panelSize = nil
                self:ClearAllPoints()
                self:SetSize(720, 620)
                self:SetPoint("CENTER")
                print("|cff00ff96TankWatch:|r " ..
                    (L["options panel was off-screen — recentered"]
                     or "options panel was off-screen — recentered"))
            end
        end)
    end)

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
    pages.layout   = buildPage("layout",   TW.OptPages.buildLayout)
    pages.bars     = buildPage("bars",     TW.OptPages.buildBars)
    pages.text     = buildPage("text",     TW.OptPages.buildText)
    pages.auras    = buildPage("auras",    TW.OptPages.buildAuras)
    pages.raid     = buildPage("raid",     TW.OptPages.buildRaid)
    pages.filters  = buildPage("filters",  TW.OptPages.buildFilters)
    pages.profiles = buildPage("profiles", TW.OptPages.buildProfiles)
    pages.about    = buildPage("about",    TW.OptPages.buildAbout)
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
        { id = "raid",     label = L["Raid Marker"] },
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
