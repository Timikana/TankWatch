<div align="center">

  <img src="logo.png" alt="TankWatch" width="180" />

  # TankWatch

  **See every tank in your group, with the boss debuffs that actually matter.**

  [![CurseForge](https://img.shields.io/badge/CurseForge-TankWatch-orange?logo=curseforge)](https://www.curseforge.com/wow/addons/tankwatch)
  [![GitHub release](https://img.shields.io/github/v/release/Timikana/TankWatch?label=Release)](https://github.com/Timikana/TankWatch/releases)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
  ![WoW Version](https://img.shields.io/badge/WoW-12.0%20Midnight-blue)

</div>

---

## What it does

TankWatch detects every tank in your party or raid (anyone with the **Tank** role assigned, or marked with `/maintank`) and shows them as a clean stack of frames with health bars and the **boss-cast debuffs** stacking on them — with the **timer rendered big** in the middle of each icon, because that's what tanks and healers need to read at a glance.

Originally inspired by the fact that nobody really does this outside of ElvUI's tank module, but ElvUI is overkill if you just want a focused, lightweight tool.

## Features

- **Auto-detection** of tanks in party / raid via role AND `/maintank`, with manual force-include for unassigned tanks
- **Boss-cast debuff filter** with per-spell whitelist + blacklist
- **Big yellow timer** centered on each icon (the prominent value)
- **Stack count** in the corner, fully positionable + sizable
- **Per-character profiles** with import/export (base64-encoded for clean copy-paste)
- **Custom textures and fonts** via LibSharedMedia
- **Movable + lockable** with snap-to-edge and screen clamping
- **Minimap button** (left-click options, right-click mover, drag to reposition)
- **Visibility scope**: show only in raid, in any group, or always
- **Test mode** (1 to 8 fake tanks with sample debuffs)
- **French + English** localization
- **Built for WoW 12.0 Midnight** — full secret-value handling via `C_UnitAuras.GetAuraDuration` + `GetAuraApplicationDisplayCount`, so timers and stacks display even on boss-tagged debuffs

## Installation

- **CurseForge** (recommended): https://www.curseforge.com/wow/addons/tankwatch
- **Manual**: drop `TankWatch/` into `World of Warcraft/_retail_/Interface/AddOns/`, `/reload`.

## Slash commands

| Command | Description |
|---|---|
| `/tw` | Open the options panel |
| `/tw mover` | Toggle the green-overlay drag handle |
| `/tw test N` | Simulate N tanks (0 to 8) with fake debuffs |
| `/tw reset` | Wipe all settings and reload the UI |
| `/tw debug` | Print roster role / maintank info |
| `/tw auradebug` | Print every HARMFUL aura on each tank unit |
| `/tankwatch` | Long alias for `/tw` |

## Bundled libraries

LibStub, CallbackHandler-1.0, LibSharedMedia-3.0

## License

[MIT](LICENSE)
