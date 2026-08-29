local addonName, TW = ...

-- ============================================================
-- PRIVATE AURAS (Midnight 12.0+)
-- ------------------------------------------------------------
-- Some boss debuffs in 12.0 are "private auras" — Blizzard renders
-- them natively via C_UnitAuras.AddPrivateAuraAnchor and never
-- exposes their data through GetAuraSlots / GetAuraDataBySlot / the
-- UNIT_AURA event payload. Addons can host the icon but can't read
-- name / spellId / stacks. This is THE missing piece that makes
-- DandersFrames / Cell see boss debuffs we don't.
--
-- The flow:
--   1. Per tank frame: create N host Frames laid out in a row
--   2. Register each host via AddPrivateAuraAnchor(unit, slot, host)
--   3. Blizzard renders the icon + cooldown swipe + count INSIDE the
--      host whenever a private aura matches the unit + slot
--   4. On rebind / unbind: RemovePrivateAuraAnchor each ID
--   5. Combat lockdown blocks the API → defer to PLAYER_REGEN_ENABLED
-- ============================================================

local function api()
    return _G.C_UnitAuras
end

local function canRegister()
    local a = api()
    return a and a.AddPrivateAuraAnchor and a.RemovePrivateAuraAnchor
end

local function inCombat()
    return InCombatLockdown and InCombatLockdown()
end

-- Ensure the per-frame host frame pool exists at the requested size,
-- with each host positioned in a row according to db settings. Hosts
-- are CreateFrame("Frame") children of the tank frame — Blizzard paints
-- the private aura texture / cooldown / count INTO each host.
local function ensureHosts(f, db)
    f._paHosts = f._paHosts or {}
    -- Inherit ALL geometry from the regular Auras section. Private auras
    -- are conceptually just debuffs the user can't see the data for —
    -- they should look indistinguishable from regular ones in the row.
    -- The `privateAuraCount` knob stays as the only private-specific
    -- option (Blizzard fills slots in priority order, so a separate
    -- count limit makes sense).
    local count   = db.privateAuraCount or 6
    local size    = db.aurasSize or 28
    local spacing = db.aurasSpacing or 2
    local anchor  = db.aurasAnchor or "RIGHT"
    local grow    = db.aurasGrowX or "RIGHT"
    local ox, oy  = db.aurasX or 0, db.aurasY or 0

    -- Inline-with-regular-debuffs mode: if the tank frame has visible
    -- regular debuff icons (tracked via f._visibleAuraCount, set by
    -- TW.UpdateAuras after rendering), anchor the first private aura
    -- host to the RIGHT of the last visible debuff icon instead of
    -- the user-configured anchor. Creates the illusion of a single
    -- continuous row mixing normal + private auras.
    local lastVisible
    if f._acActive and f._acShadow and not f._testMode then
        -- 12.1 engine mode: the visible-button count is unreadable
        -- (secret), so chain the hosts after the row's reserved box.
        -- NEVER anchor to the container itself — it carries forbidden
        -- aspects and SetPoint on a dependent frame errors; the shadow
        -- box (plain frame, same geometry) is the anchor target.
        lastVisible = f._acShadow
    elseif f._auras and f._visibleAuraCount and f._visibleAuraCount > 0 then
        lastVisible = f._auras[f._visibleAuraCount]
    end

    -- Fake icon textures for /tankw test N — distinguishable from the
    -- regular test debuff set so the user can tell which slot is which.
    -- Real combat hides these (Blizzard paints the actual aura icon).
    local TEST_PA_ICONS = {
        135725,  -- Spell_Shadow_AntiShadow
        237565,  -- Achievement_Dungeon_Ulduar80_25man
        237579,  -- Spell_Shadow_RaiseDead
        135730,  -- Spell_Shadow_AbominationExplosion
        237554,  -- Spell_Shadow_Charm
        135815,  -- Spell_Shadow_DeathPact
        135774,  -- Spell_Shadow_PsychicScream
        237568,  -- Spell_Shadow_Possession
    }

    for i = 1, count do
        local h = f._paHosts[i]
        if not h then
            h = CreateFrame("Frame", nil, f)
            -- Test-mode fake icon: ARTWORK layer so it sits above the
            -- frame background but below Blizzard's private aura paint
            -- if it ever lands (won't happen in test mode — no unit).
            local ti = h:CreateTexture(nil, "ARTWORK")
            ti:SetAllPoints(h)
            ti:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            ti:Hide()
            local bd = h:CreateTexture(nil, "OVERLAY")
            bd:SetPoint("TOPLEFT",     h, "TOPLEFT",     -1,  1)
            bd:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT",  1, -1)
            bd:SetColorTexture(0, 0, 0, 0.9)
            bd:SetDrawLayer("BACKGROUND")
            bd:Hide()
            h._testIcon, h._testBorder = ti, bd
            f._paHosts[i] = h
        end
        h:SetSize(size, size)
        h:ClearAllPoints()
        if i == 1 then
            if lastVisible then
                -- Inline continuation: attach to the last regular
                -- debuff icon, growing in the regular row direction.
                local regularGrow = (db.aurasGrowX or "RIGHT")
                local regularSpacing = (db.aurasSpacing or 2)
                if regularGrow == "LEFT" then
                    h:SetPoint("RIGHT", lastVisible, "LEFT", -regularSpacing, 0)
                else
                    h:SetPoint("LEFT", lastVisible, "RIGHT", regularSpacing, 0)
                end
            else
                -- No regular debuff visible — fall back to the
                -- standalone anchor.
                h:SetPoint(anchor, f, anchor, ox, oy)
            end
        else
            local prev = f._paHosts[i - 1]
            local side = (grow == "LEFT") and "LEFT" or "RIGHT"
            local opp  = (side == "LEFT") and "RIGHT" or "LEFT"
            local sign = (side == "LEFT") and -1 or 1
            h:SetPoint(opp, prev, side, sign * spacing, 0)
        end
        h:Show()
        -- Test-mode fake icon visibility
        if f._testMode and h._testIcon then
            local iconId = TEST_PA_ICONS[((i - 1) % #TEST_PA_ICONS) + 1]
            h._testIcon:SetTexture(iconId)
            h._testIcon:Show()
            h._testBorder:Show()
        elseif h._testIcon then
            h._testIcon:Hide()
            h._testBorder:Hide()
        end
    end
    -- Hide / shrink extra hosts beyond the requested count
    for i = count + 1, #f._paHosts do
        f._paHosts[i]:Hide()
    end
end

-- Build the iconInfo descriptor Blizzard expects. Anchored to CENTER
-- of the host frame so the icon fills it.
local function buildIconInfo(host, size)
    return {
        iconWidth  = size,
        iconHeight = size,
        iconAnchor = {
            point         = "CENTER",
            relativeTo    = host,
            relativePoint = "CENTER",
            offsetX       = 0,
            offsetY       = 0,
        },
    }
end

-- Tear down all anchors on a frame (used before re-binding or when
-- the unit goes away). Safe to call multiple times. Out-of-combat only
-- because the C API rejects mid-combat calls.
local function removeAnchors(f)
    if not canRegister() then return end
    if inCombat() then return end
    if not f._paAnchorIDs then return end
    for _, id in ipairs(f._paAnchorIDs) do
        pcall(api().RemovePrivateAuraAnchor, id)
    end
    f._paAnchorIDs = {}
end

-- (Re-)register N private aura anchors for the unit currently bound
-- on this frame. Idempotent: tears down old anchors first.
--
-- Important split: ensureHosts (SetPoint on non-secure host frames)
-- is SAFE in combat — only the C API (AddPrivateAuraAnchor /
-- RemovePrivateAuraAnchor) is gated. So in combat we still reposition
-- the hosts (keeps icons aligned with the regular row when debuffs
-- come and go) but defer the anchor (re-)registration to OOC. Blizzard
-- keeps rendering into the existing hosts even if they move.
local function applyAnchors(f, db)
    if not canRegister() then return end
    if not f then return end
    -- Allow test mode through (no _unit but _testMode is set) so the
    -- fake icons render. For non-test mode without a unit, hide hosts.
    if not f._unit and not f._testMode then
        if f._paHosts then for _, h in ipairs(f._paHosts) do h:Hide() end end
        return
    end
    if db.showPrivateAuras == false then
        removeAnchors(f)
        if f._paHosts then for _, h in ipairs(f._paHosts) do h:Hide() end end
        return
    end
    -- Always reposition the host frames — safe in combat AND in test mode.
    ensureHosts(f, db)
    -- Test mode: no real anchor registration (no unit). Hosts + fake
    -- icons are enough for layout preview.
    if f._testMode then return end
    if inCombat() then
        f._paPending = true
        return
    end
    f._paPending = nil
    removeAnchors(f)
    f._paAnchorIDs = f._paAnchorIDs or {}
    local count = db.privateAuraCount or 4
    local size  = db.privateAuraSize or 28
    for i = 1, count do
        local host = f._paHosts[i]
        if host then
            local ok, anchorID = pcall(api().AddPrivateAuraAnchor, {
                unitToken             = f._unit,
                auraIndex             = i,
                parent                = host,
                showCountdownFrame    = true,
                showCountdownNumbers  = true,
                iconInfo              = buildIconInfo(host, size),
                isContainer           = false,
            })
            if ok and anchorID then
                f._paAnchorIDs[#f._paAnchorIDs + 1] = anchorID
            end
        end
    end
end

-- ============================================================
-- PUBLIC API
-- ============================================================

-- Called from Tank.lua after a tank frame's _unit is (re)bound.
function TW:ApplyPrivateAuras(f)
    if not f then return end
    local db = TW:GetDB()
    applyAnchors(f, db)
end

-- Called for every tank frame — usually from RefreshAll / event hooks.
function TW:ApplyAllPrivateAuras()
    if not TW.TankFrames then return end
    local db = TW:GetDB()
    for i = 1, (TW.MAX_TANKS or 8) do
        local f = TW.TankFrames[i]
        if f and f._unit then
            applyAnchors(f, db)
        elseif f then
            removeAnchors(f)
            if f._paHosts then for _, h in ipairs(f._paHosts) do h:Hide() end end
        end
    end
end

-- Diagnostic: print the current private aura anchor registration state
-- for every tank frame. Invoked by /tankw paauradump. Confirms whether
-- AddPrivateAuraAnchor actually succeeded for each unit + slot — if a
-- tank has 0 anchors despite having a unit, the API rejected silently
-- and we know to investigate further.
function TW:PrintPrivateAuraDebug()
    print("|cff00ff96TankWatch:|r private aura diagnostic:")
    if not canRegister() then
        print("  C_UnitAuras.AddPrivateAuraAnchor not available on this client")
        return
    end
    if inCombat() then
        print("  |cffff8800WARNING|r: in combat — registration deferred until PLAYER_REGEN_ENABLED")
    end
    local db = TW:GetDB()
    print(string.format("  config: enabled=%s count=%d size=%d anchor=%s grow=%s",
        tostring(db.showPrivateAuras), db.privateAuraCount or 4,
        db.privateAuraSize or 28, db.privateAuraAnchor or "?",
        db.privateAuraGrowX or "?"))
    local seen = false
    for i = 1, (TW.MAX_TANKS or 8) do
        local f = TW.TankFrames and TW.TankFrames[i]
        if f then
            local unit = f._unit or "nil"
            local nAnchors = f._paAnchorIDs and #f._paAnchorIDs or 0
            local nHosts = f._paHosts and #f._paHosts or 0
            local pending = f._paPending and " |cffff8800[PENDING]|r" or ""
            local visible = f:IsShown() and "shown" or "hidden"
            if f._unit or nAnchors > 0 or nHosts > 0 then
                seen = true
                print(string.format("  tank[%d] unit=%s (%s) anchors=%d hosts=%d%s",
                    i, tostring(unit), visible, nAnchors, nHosts, pending))
            end
        end
    end
    if not seen then print("  (no tank frames active)") end
end

-- Flush any deferred private-aura setup that was delayed because the
-- C API can't be called during combat lockdown. Hooked into the
-- PLAYER_REGEN_ENABLED handler in Tank.lua.
function TW:FlushPendingPrivateAuras()
    if not TW.TankFrames then return end
    local db = TW:GetDB()
    for i = 1, (TW.MAX_TANKS or 8) do
        local f = TW.TankFrames[i]
        if f and f._paPending and f._unit then
            applyAnchors(f, db)
        end
    end
end
