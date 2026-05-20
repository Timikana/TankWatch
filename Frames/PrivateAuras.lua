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
    local count   = db.privateAuraCount or 4
    local size    = db.privateAuraSize or 28
    local spacing = db.privateAuraSpacing or 2
    local anchor  = db.privateAuraAnchor or "LEFT"
    local grow    = db.privateAuraGrowX or "RIGHT"
    local ox, oy  = db.privateAuraX or 0, db.privateAuraY or -32

    for i = 1, count do
        local h = f._paHosts[i]
        if not h then
            h = CreateFrame("Frame", nil, f)
            f._paHosts[i] = h
        end
        h:SetSize(size, size)
        h:ClearAllPoints()
        if i == 1 then
            h:SetPoint(anchor, f, anchor, ox, oy)
        else
            local prev = f._paHosts[i - 1]
            local side = (grow == "LEFT") and "LEFT" or "RIGHT"
            local opp  = (side == "LEFT") and "RIGHT" or "LEFT"
            local sign = (side == "LEFT") and -1 or 1
            h:SetPoint(opp, prev, side, sign * spacing, 0)
        end
        h:Show()
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
local function applyAnchors(f, db)
    if not canRegister() then return end
    if not f or not f._unit then return end
    if db.showPrivateAuras == false then
        removeAnchors(f)
        if f._paHosts then for _, h in ipairs(f._paHosts) do h:Hide() end end
        return
    end
    if inCombat() then
        f._paPending = true
        return
    end
    f._paPending = nil
    removeAnchors(f)
    ensureHosts(f, db)
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
