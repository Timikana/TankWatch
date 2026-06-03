local addonName, TW = ...
local L = TW.L

local h = TW._OptHelpers
local makeSection         = h.makeSection
local addTooltip          = h.addTooltip
local _registerInSection  = h.registerInSection

TW.OptPages = TW.OptPages or {}

local CHANGELOG_TEXT = L["CHANGELOG_BODY"] or [[
## v1.4.10

|cffffd700Fixed|r — Missing boss debuffs on tank / co-tank frames
- In Midnight 12.0 boss debuffs are often "secret-tagged" so the
  data isn't readable in Lua. TankWatch now matches DandersFrames'
  full pattern: event-driven UNIT_AURA cache fed by addedAuras /
  updatedAuraInstanceIDs / removedAuraInstanceIDs, dual-path
  rescan (GetAuraSlots + GetAuraDataByIndex fallback), single
  HARMFUL truthy-check categorization, sort by expirationTime,
  SetCooldownFromDurationObject for secret-safe swipe,
  GetAuraApplicationDisplayCount for stacks. Icons + cooldown +
  stacks render even when name / spellID stay sealed by Blizzard.

|cffffd700New|r — Private aura anchors (boss-rendered icons)
- Some boss debuffs in 12.0 are "private auras" Blizzard renders
  natively — invisible to addon Lua. We register
  C_UnitAuras.AddPrivateAuraAnchor per tank slot; Blizzard paints
  the icon, cooldown, and count directly into our frame. New
  dedicated row below the main debuff row, configurable in
  Auras tab (count / size / spacing / anchor / offset).

|cffffd700New|r — Global spellID in tooltips
- TooltipDataProcessor hook appends "spellID NNNN" to every
  spell / aura tooltip in the UI — BuffFrame, action bars, /cast
  preview, raid frames, etc. Toggle in Auras tab.

|cffffd700New|r — Selection / hover border on tank frames
- 2px animated border around each tank frame: gold when targeted,
  cyan when focused, white on mouseover. Pulse animation (BOUNCE
  alpha) toggle, thickness slider (1-6 px), 3 color pickers.
  Ported from BossWatch.

|cffffd700New|r — Granular whitelist / blacklist sharing
- Per-list Export / Import buttons (Filtres tab) serialize the
  current spellID list as a comma-separated string. Easy to share
  on Discord without exporting the full profile (TW2!).

|cffffd700New|r — Default junk blacklist seeded
- 8 well-known noise spellIDs pre-added to the blacklist (Sated,
  Exhaustion, Temporal Displacement, Fatigued, Insanity, etc.).
  One-time migration via _blacklistSeededV1 flag — entries you
  remove stay removed.

|cffffd700New|r — Targeted aura-only reset
- "Réinitialiser les auras" button (Auras tab) + /tankw resetauras
  slash. Wipes only the aura-related settings + re-seeds defaults.
  /tankw reset (full profile + ReloadUI) stays for the nuclear option.

|cffffd700New|r — Diagnostic slash commands
- /tankw auradebug : dump every HARMFUL aura per tank with spellID
  + stacks + filter classification (RAID/RAID_IN_COMBAT/IMPORTANT).
- /tankw paauradump : list private aura anchor registration state
  per tank (count, host count, pending flag, config).
- /tankw renderdebug : toggle live UpdateAuras render trace.

|cffffd700Fixed|r — Filter mode dropdown simplified
- Dropped redundant "Boss-cast only" option (was identical to
  "All debuffs" since beta7's iteration-trust refactor). Now two
  modes: "Tous les debuffs (la blacklist filtre)" and "Whitelist
  uniquement". Migration remaps existing BOSS profile values to ALL.

## v1.4.9

|cffffd700New|r — Right-click + raid markers on tank frames
- Right-click a tank frame to open the Blizzard unit menu (Set Focus,
  Set Raid Target submenu, etc.).
- Shift+LeftClick cycles the raid marker on that tank.
- Ctrl+LeftClick sets focus directly.
- The raid marker overlay shows on each tank frame when a marker is
  set. New dedicated "Raid Marker" tab to tweak anchor / offset / size
  / alpha; toggles in Layout > General gate click actions and the
  overlay separately.

|cffffd700Fixed|r — Raid marker icon now displays on real tanks
- In Midnight 12.0 GetRaidTargetIndex returns a "secret value" even
  for friendly units, so the overlay never appeared in real groups
  (only test mode worked). Now routed through the texture
  :SetSpriteSheetCell method that accepts secret indices C-side.

|cffffd700Fixed|r — Test mode "Off" restores real tanks
- Turning test mode off was hiding every frame without rebinding to
  the real roster; frames stayed hidden until the next roster event.
  Test off now refreshes the tank list immediately.

|cffffd700New|r — Death indicator
- When a tank dies, the frame dims to 45% and a skull overlay
  appears at the center so it's instantly obvious without having
  to read 0/X HP.

|cffffd700New|r — Bug report helper
- /tankw bugreport opens a popup pre-filled with everything triage
  needs: version, client (retail/Classic), build, screen size, active
  profile + modes, whitelist/blacklist counts, visible tanks, and
  the last Lua error if BugGrabber is installed. Ctrl+A → Ctrl+C →
  paste into Discord or GitHub.

|cffffd700Improved|r — Single global aura ticker
- Replaced the per-icon OnUpdate handlers (up to 40 of them at a
  full 8 tanks × 5 auras) with one shared 10 Hz ticker that walks
  every visible icon. Lower CPU at zero visual cost.

## v1.4.8

|cffffd700Fixed|r — Aura font in combat
- New debuff icons created mid-combat were keeping the default
  Blizzard font instead of the one configured in Text > Font. The
  configured font is now re-applied whenever the icon pool grows.

## v1.4.7

|cffffd700Fixed|r — Options panel off-screen rescue
- The options window itself now gets the same protection as the tank
  container: if the saved size/position lands the panel entirely
  outside the viewport (saved on a 4K screen, then playing on 1080p),
  it auto-recenters at the default 720×620 with a chat notice.
- Restored size is also clamped to the screen so the panel never ends
  up bigger than the monitor.

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

function TW.OptPages.buildAbout(page)
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
        if TW._OptPanel then TW._OptPanel:SetAlpha(v) end
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
        "|cffffff00/tankw bugreport|r — " .. (L["copy system + addon state for bug reports"] or "copy system + addon state for bug reports") .. "\n" ..
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

