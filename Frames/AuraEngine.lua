local addonName, TW = ...

-- ============================================================
-- AURA ENGINE (WoW 12.1+ — AuraContainer intrinsic path)
-- ------------------------------------------------------------
-- 12.1 model: reading aura data in Lua is sealed in combat (index/
-- slot/instanceID reads hard-error, UNIT_AURA payload fully secret),
-- but DISPLAY is not. The addon CREATES + STYLES the buttons;
-- Blizzard's secure code FILLS + DRIVES them. We declare the query
-- (filter string + candidateFilters evaluated C-side against the
-- real secret data) and hand over rendering entirely — we never
-- observe aura contents.
--
-- Pattern sources (both verified in-game on 12.1 builds):
--   DandersFrames Frames/AuraContainer.lua — build order, no-formatter
--     stack rule, CanBeAccessedInContext guard, flow layout.
--   BigWigs_Plugins/Auras.lua — single "HARMFUL" group with
--     sortMethod = 4 (Enum.UnitAuraSortRule.ExpirationOnly),
--     excludeSpellIDs candidate filter, SetApplicationCount(fs).
--
-- Build order (proven live in combat — do not reorder):
--   CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
--   -> geometry -> SetUnit -> AddAuraGroup(...) -> SetEnabled(true) LAST
--   (SetEnabled is what arms the container's own UNIT_AURA parse).
--
-- Hard rules learned from DF:
--   * NEVER pass a formatter to SetApplicationCount — Blizzard's
--     formatter path runs in Lua with the SECRET count and bricks the
--     container for the session. The bare-FontString path renders
--     secure-side and is the only secret-safe option.
--   * Create every region with its final parent up front — buttons
--     stamp ForbiddenAspect ChangeParent on bound regions.
--   * Never branch on a button's IsShown / contents — secret. Only
--     touch existing buttons behind CanBeAccessedInContext().
--   * Containers are built/mutated out of combat only.
-- ============================================================

local CreateFrame = CreateFrame

TW.AuraEngine = {}
local AE = TW.AuraEngine

-- nil = not probed yet (or probe deferred by combat), true/false = final
local supported = nil

local function probeSupported()
    if InCombatLockdown and InCombatLockdown() then return nil end
    local toc = select(4, GetBuildInfo())
    if type(toc) ~= "number" or toc < 120100 then return false end
    if not (AuraUtil and AuraUtil.IsValidFilterString) then return false end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent,
                        "CustomAuraContainerTemplate")
    if not ok or not c then return false end
    local hasGroups = type(c.AddAuraGroup) == "function"
    pcall(c.Hide, c)
    return hasGroups
end

function AE.IsSupported()
    if supported == nil then supported = probeSupported() end
    return supported == true
end

function AE.IsActive(f)
    return f and f._acActive or false
end

-- ============================================================
-- CANDIDATE FILTERS
-- ------------------------------------------------------------
-- The whitelist/blacklist map 1:1 onto the engine's include/exclude
-- spell-ID candidate filters — evaluated by Blizzard's secure matcher
-- (Blizzard_AuraContainer runs with UseSecureEnvironment) against the
-- REAL aura data, secrets included. Same semantics as the legacy
-- passesFilter: WHITELIST mode shows only listed IDs; ALL mode shows
-- everything HARMFUL minus the blacklist.
-- ============================================================
local function buildCandidateFilters(db)
    local cf = {}
    local mode = db.auraFilterMode or "ALL"
    if mode == "WHITELIST" then
        local inc, n = {}, 0
        for id in pairs(db.auraWhitelist or {}) do
            if type(id) == "number" then inc[id] = true; n = n + 1 end
        end
        if n > 0 then cf.includeSpellIDs = inc end
    else
        local exc, n = {}, 0
        for id in pairs(db.auraBlacklist or {}) do
            if type(id) == "number" then exc[id] = true; n = n + 1 end
        end
        if n > 0 then cf.excludeSpellIDs = exc end
    end
    return cf
end

-- Cheap config signature so Apply() is a no-op when nothing relevant
-- changed (it runs on every ApplyLayout pass).
local function listSig(t)
    if not t then return "-" end
    local ids = {}
    for id in pairs(t) do ids[#ids + 1] = tostring(id) end
    table.sort(ids)
    return table.concat(ids, ",")
end

local function buildSig(db, unit)
    return table.concat({
        tostring(unit),
        tostring(db.showAuras), tostring(db.aurasMaxCount),
        tostring(db.aurasSize), tostring(db.aurasSpacing),
        tostring(db.aurasAnchor), tostring(db.aurasGrowX),
        tostring(db.aurasX), tostring(db.aurasY),
        tostring(db.compactMode), tostring(db.showClassIcon),
        tostring(db.auraFilterMode),
        tostring(db.auraStackAnchor), tostring(db.auraStackX), tostring(db.auraStackY),
        tostring(db.auraTimerAnchor), tostring(db.auraTimerX), tostring(db.auraTimerY),
        tostring(db.auraTimerShow),
        listSig(db.auraWhitelist), listSig(db.auraBlacklist),
    }, "|")
end

-- ============================================================
-- BUTTON REGIONS
-- ------------------------------------------------------------
-- Same visual recipe as the legacy CreateAuraButton: zoomed icon,
-- 1px black backdrop, cooldown swipe without numbers, HUGE yellow
-- timer + stack count drawn above the swipe. Blizzard writes the
-- contents; we only own look & placement.
-- ============================================================
local function styleButton(f, btn, db)
    -- Engine-owned buttons can turn forbidden under us at any moment
    -- (the client can reclaim/re-init a slot's subtree) — every touch
    -- is pcall'd so a throw costs one icon, not the whole pass.
    local size = db.aurasSize or 28
    pcall(btn.SetSize, btn, size, size)
    if TW.ApplyAuraTextLayout then pcall(TW.ApplyAuraTextLayout, btn, db) end
end

-- ============================================================
-- DURATION TEXT FORMAT
-- ------------------------------------------------------------
-- Blizzard's default duration text is "3 s" (localized unit suffix) —
-- not our look. A NumericRuleFormatter reproduces the legacy compact
-- format ("45" → "2m" → "1h", bare number under a minute) and is
-- evaluated C-SIDE against the secret remaining time, so it's fully
-- combat-safe (unlike SetApplicationCount, duration formatters are
-- explicitly supported — they ride the DurationTextBinding).
-- Breakpoints are DF's field-tested NUMBER recipe: the seconds band
-- CEILS (countdown reads 3, 2, 1, gone — floor made the last "1"
-- linger two seconds), promotion to m/h at Blizzard's 1.5x thresholds,
-- quotient rounds up to match the game's own frames.
-- ============================================================
local PROMOTE_MIN  = 1 + 1.5 * 60    -- 91s  → "2m"
local PROMOTE_HOUR = 1 + 1.5 * 3600  -- 5401s → "2h"

local durFormatter -- nil = not built yet, false = unavailable
local function getDurationFormatter()
    if durFormatter ~= nil then return durFormatter or nil end
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
            and Enum and Enum.NumericRuleFormatRounding) then
        durFormatter = false
        return nil
    end
    local ok, f = pcall(function()
        local down = Enum.NumericRuleFormatRounding.Down
        local up   = Enum.NumericRuleFormatRounding.Up
        local fmt = C_StringUtil.CreateNumericRuleFormatter()
        fmt:AddBreakpoint({ threshold = 0, step = 1, rounding = up, min = 1,
                            format = "%d" })
        fmt:AddBreakpoint({ threshold = PROMOTE_MIN, step = 1, rounding = down, min = 1,
                            format = "%dm", components = { { div = 60, rounding = up } } })
        fmt:AddBreakpoint({ threshold = PROMOTE_HOUR, step = 1, rounding = down, min = 1,
                            format = "%dh", components = { { div = 3600, rounding = up } } })
        return fmt
    end)
    durFormatter = ok and f or false
    return durFormatter or nil
end

-- SetDurationText options: build 68914 reshaped them to { binding | ... }
-- (flat keys silently ignored); older builds read the flat { formatter }.
-- The honest probe for the new shape is the options processor itself.
-- One template binding serves every button (Assign copies it wholesale).
local durBinding -- nil = not built yet, false = unavailable
local function getDurationTextOpts()
    local fmt = getDurationFormatter()
    if not fmt then return nil end
    if C_AuraContainerUtil
       and type(C_AuraContainerUtil.ProcessCustomAuraButtonDurationTextOptions) == "function" then
        if durBinding == nil then
            if C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
                local ok, b = pcall(function()
                    local bind = C_DurationUtil.CreateDurationTextBinding()
                    -- A fresh binding is UNCONFIGURED and Assign replaces the
                    -- button binding wholesale — it must carry the formatter
                    -- itself and be enabled, or rows render no text at all.
                    bind:SetFormatter(fmt)
                    bind:SetEnabled(true)
                    return bind
                end)
                durBinding = (ok and b) or false
            else
                durBinding = false
            end
        end
        if durBinding then return { binding = durBinding } end
        return nil
    end
    return { formatter = fmt }
end

-- The flow layout sizes its cells from the GROUP layout table, not from
-- the button's own SetSize — without this the engine re-stamps its
-- default cell size (32px) on every parse and the size slider "does
-- nothing". Field names changed at build 68914; ship both generations
-- (unknown keys are ignored).
local function buildGroupLayout(db)
    local size    = db.aurasSize or 28
    local spacing = db.aurasSpacing or 2
    return {
        elementWidth    = size,
        elementHeight   = size,
        elementSpacing  = spacing, -- 68914+
        lineSpacing     = spacing, -- 68914+
        groupSpacing    = 0,       -- 68914+
        elementSpacingX = spacing, -- pre-68914 twin
        elementSpacingY = spacing, -- pre-68914 twin
        gapX            = 0,       -- pre-68914 twin
    }
end

local function initButton(f, btn)
    if btn._twInit then
        styleButton(f, btn, TW:GetDB())
        return
    end
    btn._twInit = true

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon
    pcall(btn.SetIcon, btn, icon)

    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 0.9)
    btn.border = border

    local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cd:SetAllPoints(btn)
    cd:SetHideCountdownNumbers(true)
    cd:SetDrawEdge(false); cd:SetDrawSwipe(true)
    btn.cd = cd
    pcall(btn.SetDurationCooldown, btn, cd)

    -- Timer + stacks live on the cooldown frame so they draw above the
    -- swipe — same trick as the legacy button.
    local timer = cd:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
    timer:SetPoint("CENTER", btn, "CENTER", 0, 0)
    timer:SetTextColor(1, 0.9, 0.1)
    timer:SetShadowColor(0, 0, 0, 1)
    timer:SetShadowOffset(1, -1)
    timer:SetDrawLayer("OVERLAY", 7)
    btn.timer = timer
    if btn.SetDurationText then
        -- Custom compact format ("45" → "2m" → "1h") when the formatter
        -- API is available; otherwise Blizzard's default text ("3 s").
        local opts = getDurationTextOpts()
        if not (opts and pcall(btn.SetDurationText, btn, timer, opts)) then
            if not pcall(btn.SetDurationText, btn, timer) then
                pcall(btn.SetDurationText, btn, timer, {})
            end
        end
    end

    local stacks = cd:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    stacks:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    stacks:SetJustifyH("RIGHT")
    stacks:SetTextColor(1, 1, 1)
    stacks:SetShadowColor(0, 0, 0, 1)
    stacks:SetShadowOffset(1, -1)
    stacks:SetDrawLayer("OVERLAY", 7)
    btn.stacks = stacks
    -- ⚠ bare FontString, NO formatter, NO options with formatter — see
    -- header. Blizzard renders counts > 1 secure-side.
    if btn.SetApplicationCount then
        pcall(btn.SetApplicationCount, btn, stacks)
    end

    -- Register the texts so TW:ApplyFonts (font face / timer & stack
    -- size sliders) reaches them, and apply the current spec right away
    -- — buttons can spawn mid-combat and must not wait for a refresh.
    f._acTexts = f._acTexts or {}
    f._acTexts[#f._acTexts + 1] = { timer = timer, stacks = stacks }
    if TW.GetAuraFontSpec then
        local file, timerSz, stackSz, strongOutline = TW:GetAuraFontSpec()
        pcall(timer.SetFont, timer, file, timerSz, strongOutline)
        pcall(stacks.SetFont, stacks, file, stackSz, strongOutline)
    end

    -- Native tooltip on hover; clicks pass through to the world.
    if btn.SetMouseClickEnabled then pcall(btn.SetMouseClickEnabled, btn, false) end
    if btn.SetMouseMotionEnabled then pcall(btn.SetMouseMotionEnabled, btn, true) end

    styleButton(f, btn, TW:GetDB())
end

-- ============================================================
-- GEOMETRY
-- ------------------------------------------------------------
-- The container is a fixed reserved box the size of the full row
-- (maxCount icons); buttons flow inside it from the row's origin
-- side. Placement mirrors the legacy LayoutAuras anchor logic.
-- ============================================================
local function mirrorAnchor(a)
    if a == "CENTER" then return "CENTER" end
    if a == "TOP" then return "BOTTOM" end
    if a == "BOTTOM" then return "TOP" end
    if a:find("LEFT") then return (a:gsub("LEFT", "RIGHT")) end
    if a:find("RIGHT") then return (a:gsub("RIGHT", "LEFT")) end
    return a
end

local function applyGeometry(f, c, db)
    local size     = db.aurasSize or 28
    local spacing  = db.aurasSpacing or 2
    local maxCount = db.aurasMaxCount or 5
    local w = maxCount * size + math.max(0, maxCount - 1) * spacing

    -- The container inherits forbidden aspects (UntrustedLayoutScript-
    -- Execution): NOTHING of ours may anchor TO it — SetPoint on a
    -- dependent frame errors. Since we own the row geometry anyway, it
    -- lives on a plain invisible shadow box; the container fills the
    -- box (protected-depends-on-unprotected is the allowed direction),
    -- and anything chaining after the row (private aura hosts) anchors
    -- to the shadow, never to the container.
    local box = f._acShadow
    if not box then
        box = CreateFrame("Frame", nil, f)
        f._acShadow = box
    end
    box:SetSize(math.max(w, size), size)

    local anchor = db.aurasAnchor or "RIGHT"
    local growX  = db.aurasGrowX or "RIGHT"
    local compact = db.compactMode and true or false
    if compact then growX = "RIGHT" end

    box:ClearAllPoints()
    if compact and db.showClassIcon and f.classIcon and f.classIcon:IsShown() then
        box:SetPoint("LEFT", f.classIcon, "RIGHT", 4, 0)
    elseif compact then
        box:SetPoint("LEFT", f, "LEFT", 2, 0)
    else
        box:SetPoint(mirrorAnchor(anchor), f, anchor, db.aurasX or 0, db.aurasY or 0)
    end
    pcall(c.ClearAllPoints, c)
    pcall(c.SetAllPoints, c, box)

    -- Flow layout — every setter pcall'd + feature-checked so a PTR
    -- rename degrades to Blizzard's default flow instead of erroring.
    local originLeft = (growX ~= "LEFT")
    if c.SetFlowLayoutAnchorPoint then
        pcall(c.SetFlowLayoutAnchorPoint, c, originLeft and "LEFT" or "RIGHT")
    end
    if c.SetFlowLayoutGrowthDirection and AnchorUtil and AnchorUtil.FlowDirection then
        local FD = AnchorUtil.FlowDirection
        local h = originLeft and (FD.Right or FD.RIGHT) or (FD.Left or FD.LEFT)
        local v = FD.Down or FD.DOWN
        if h ~= nil and v ~= nil then
            pcall(c.SetFlowLayoutGrowthDirection, c, h, v)
        end
    end
    if c.SetFlowLayoutPadding then pcall(c.SetFlowLayoutPadding, c, spacing, spacing) end
    if c.SetFlowLayoutMaximumLineSize then pcall(c.SetFlowLayoutMaximumLineSize, c, w + 1) end
end

-- ============================================================
-- APPLY
-- ------------------------------------------------------------
-- Called from ApplyLayout for every tank frame (already OOC-gated by
-- the _pendingLayout machinery). Returns true when the engine owns
-- aura rendering for this frame — the caller must then park the
-- legacy buttons and skip TW.UpdateAuras.
-- ============================================================
local function parkContainer(f)
    if f._ac then
        pcall(f._ac.SetEnabled, f._ac, false)
        f._ac:Hide()
    end
    f._acActive = false
    f._acSig = nil
end

function AE.Apply(f, db)
    if not f then return false end
    if supported == nil then supported = probeSupported() end
    if supported ~= true then return false end
    db = db or TW:GetDB()

    -- Test mode previews through the legacy painted buttons (the
    -- container can't be fed fake auras) — park and hand back.
    if f._testMode then
        parkContainer(f)
        return false
    end

    -- Nothing to render: engine still "owns" the surface (returns true)
    -- so stale legacy buttons don't reappear.
    if not db.showAuras or not f._unit then
        parkContainer(f)
        return true
    end

    -- Defensive: ApplyLayout should never run in combat, but a stray
    -- in-combat call must not touch the container. Keep the current
    -- one running untouched; the regen flush re-applies.
    if InCombatLockdown and InCombatLockdown() then
        return f._ac ~= nil
    end

    local sig = buildSig(db, f._unit)
    if f._ac and f._acActive and f._acSig == sig then
        f._ac:Show()
        return true
    end

    local c = f._ac
    if not c then
        local ok
        ok, c = pcall(CreateFrame, "AuraContainer", nil, f,
                      "CustomAuraContainerTemplate")
        if not ok or not c then
            supported = false
            return false
        end
        f._ac = c
    end

    -- Disarm while mutating, re-arm last.
    pcall(c.SetEnabled, c, false)
    applyGeometry(f, c, db)
    pcall(c.SetUnit, c, f._unit)

    local cf = buildCandidateFilters(db)
    local maxCount = db.aurasMaxCount or 5
    if not f._acGroupAdded then
        local okG = pcall(c.AddAuraGroup, c, "main", "HARMFUL", {
            maxFrameCount    = maxCount,
            initializeFrame  = function(btn) initButton(f, btn) end,
            sortMethod       = 4, -- Enum.UnitAuraSortRule.ExpirationOnly
            sortDirection    = 0, -- Enum.UnitAuraSortDirection.Normal
            candidateFilters = cf,
            layout           = buildGroupLayout(db),
        })
        if not okG then
            pcall(c.Hide, c)
            supported = false
            return false
        end
        f._acGroupAdded = true
    else
        if c.SetAuraGroupMaxFrameCount then
            pcall(c.SetAuraGroupMaxFrameCount, c, "main", maxCount)
        end
        if c.SetAuraGroupCandidateFilters then
            pcall(c.SetAuraGroupCandidateFilters, c, "main", cf)
        end
        -- Re-push the cell layout — button SetSize alone is stomped by
        -- the flow on the next parse (see buildGroupLayout).
        if c.SetAuraGroupLayout then
            pcall(c.SetAuraGroupLayout, c, "main", buildGroupLayout(db))
        end
    end

    -- Re-style buttons the container already spawned (size / text
    -- anchors may have changed). Buttons are forbidden while auras are
    -- secret — only touch the accessible ones.
    if c.GetAuraGroupFrameCount and c.GetAuraGroupFrame then
        local okN, n = pcall(c.GetAuraGroupFrameCount, c, "main")
        if okN and type(n) == "number" then
            for i = 1, n do
                local okB, btn = pcall(c.GetAuraGroupFrame, c, "main", i)
                if okB and btn and btn._twInit and btn.CanBeAccessedInContext then
                    local okA, acc = pcall(btn.CanBeAccessedInContext, btn)
                    if okA and acc == true then styleButton(f, btn, db) end
                end
            end
        end
    end

    c:Show()
    pcall(c.SetEnabled, c, true) -- LAST — arms the parse + event feed
    if c.UpdateAllAuras then pcall(c.UpdateAllAuras, c) end

    f._acSig = sig
    f._acActive = true
    return true
end

-- ============================================================
-- DIAGNOSTIC (/tankw acdebug)
-- ============================================================
function AE.Debug()
    if supported == nil then supported = probeSupported() end
    print(string.format("|cff00ff96TankWatch:|r AuraEngine supported=%s (toc=%s)",
        tostring(supported), tostring(select(4, GetBuildInfo()))))
    if not TW.TankFrames then return end
    for i = 1, (TW.MAX_TANKS or 8) do
        local f = TW.TankFrames[i]
        if f and (f._unit or f._testMode or f._ac) then
            local n = "?"
            if f._ac and f._ac.GetAuraGroupFrameCount then
                local ok, v = pcall(f._ac.GetAuraGroupFrameCount, f._ac, "main")
                if ok then n = tostring(v) end
            end
            print(string.format(
                "  [%d] unit=%s test=%s container=%s active=%s buttons=%s",
                i, tostring(f._unit), tostring(f._testMode or false),
                tostring(f._ac ~= nil), tostring(f._acActive or false), n))
        end
    end
end

-- Warm the capability probe at login so the first ApplyLayout doesn't
-- pay for it (and so a /reload mid-combat stays on nil -> retried OOC).
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    if supported == nil then supported = probeSupported() end
end)
