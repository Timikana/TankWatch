# Changelog

## v1.2.2

### New
- Reorganized options panel for clearer structure
  - Range Fade controls moved to **Layout** (where the rest of the frame
    behavior lives)
  - Health bar texture and color merged into a single **Health bar** section
  - Aura **Size** and **Layout** sections merged into one **Icons** section
  - Panel opacity slider moved to the **About** tab under a new
    **Options window** section
- Added 552 new translations across 8 languages: German, Spanish, Italian,
  Brazilian Portuguese, Russian, Korean, Simplified Chinese and Traditional
  Chinese now cover all the main section headers and common labels
  (Enable, Anchor, Width, color modes, anchor points, etc.)
- Tooltips now also appear when hovering the steppers and slider thumb,
  not just the body of a slider

---

## v1.2.1

### New
- Added a **Discord** invite link in the About tab (support, bug reports,
  suggestions): https://discord.gg/uFmxwexQ4P

---

## v1.2.0

### New
- **Absorb shield** support: tanks now show their active absorb (Death
  Strike, Word of Glory, Sanguine Ground, etc.) as a translucent shield
  bar overlaid on the health bar
  - Sky-blue color by default, fully customizable
  - Choose any LibSharedMedia status-bar texture
  - Shield can grow from the right edge (default) or the left edge
- Tested on every tank class — shows up reliably in raids and dungeons

### Improved
- Mover handle now floats above tank frames so it can be dragged even
  when a real tank is showing in the slot
- Cleaner spacing on the Bars tab (no more overlap between the absorb
  texture preview and the side dropdown)
- HP text rendering hardened against several edge cases on group members

### Fixed
- Removed the Percent / Current+Percent HP formats — they couldn't be
  computed reliably on group members in 12.0 and would show garbage in
  some situations. The Current and Current/Max formats both work.

### Packaging
- All embedded libraries (LibStub, CallbackHandler, LibSharedMedia,
  LibDataBroker) now appear properly in CurseForge's "Embedded Libraries"
  list with their correct versions

---

## v1.1.5

- Profile import overwrite confirmation popup translated in 9 languages
  (French + 8 stubs)

## v1.1.4

- When importing a profile with a name that already exists, you now get
  a confirmation prompt: **"Profile 'X' already exists. Overwrite?"**
  Click Yes to overwrite or No to cancel

## v1.1.3

- Fixed the green portrait placeholder that appeared instead of the
  TankWatch logo at the top-left of the options panel on some setups

## v1.1.2

- Shipped the logo file in the package so the portrait icon now shows
  correctly when installing through CurseForge

## v1.1.1

- Fixed a crash on the profile name dialog (clicking New / Import would
  fail with a Lua error)

---

## v1.1.0

### New — Modern options panel
- Complete redesign of the options window using Blizzard's modern panel
  template (the same one used by the in-game Adventure Guide and
  Encounter Journal)
- Press **ESC** to close the panel
- Adjustable **panel opacity** so the options window doesn't get in the
  way of seeing your group during configuration
- Every control now has a **descriptive tooltip** explaining what it
  does — hover over any slider, dropdown or checkbox
- Sections are visually separated with gold headers and dividers
- Long pages scroll smoothly when needed
- New **CurseForge** and **Wago.io** links in the About tab

---

## v1.0.4

- TankWatch now appears automatically in **Titan Panel** and
  **ChocolateBar** with a clickable launcher (left-click options,
  right-click mover)
- New **NEW** badge on freshly added options after each update — the
  badge disappears the first time you hover or click the control
- Added German, Spanish, Italian, Brazilian Portuguese, Russian, Korean,
  Simplified Chinese and Traditional Chinese locale stubs (tab names
  translated, more strings to come)

## v1.0.3

- Released on Wago.io alongside CurseForge

## v1.0.2

- Improved background customization (color or texture, custom or class
  color, alpha control)
- Better mover UX: right-click while moving now locks the position

## v1.0.1

- Fixed a critical issue that could prevent clicking on bag items while
  TankWatch was loaded
- Mover overlay now matches the actual visible content size

## v1.0.0

- First public release on CurseForge
- Tank detection in raid (via group role or `/maintank`), 5-man party,
  or solo
- Boss-cast debuff icons with the **stack count rendered HUGE in the
  icon center** — the headline feature
- Whitelist / blacklist by spell ID (great for M+ trash debuffs)
- Per-character profiles with base64 export / import
- Minimap button, slash commands (`/tw`, `/tankwatch`)
- French translation included
