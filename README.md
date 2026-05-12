<div align="center">

  <img src="logo.png" alt="TankWatch" width="180" />

  # TankWatch

  **See every tank in your group, with the boss debuffs that actually matter.**

  [![CurseForge](https://img.shields.io/badge/CurseForge-TankWatch-orange?logo=curseforge)](https://www.curseforge.com/wow/addons/tankwatch)
  [![Wago](https://img.shields.io/badge/Wago-TankWatch-purple)](https://addons.wago.io/addons/tankwatch)
  [![GitHub release](https://img.shields.io/github/v/release/Timikana/TankWatch?label=Release)](https://github.com/Timikana/TankWatch/releases)
  [![Discord](https://img.shields.io/badge/Discord-Support-5865F2?logo=discord&logoColor=white)](https://discord.gg/uFmxwexQ4P)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

  ![Retail 12.0](https://img.shields.io/badge/Retail-12.0%20Midnight-blue)
  ![MoP Classic 5.5](https://img.shields.io/badge/Classic-MoP%205.5-green)

</div>

---

## What it does

TankWatch detects every tank in your party or raid — anyone with the **Tank** role, or marked with `/maintank` — and shows them as a clean stack of frames with the **boss debuffs stacking on them**, the **timer rendered big** in the middle of each icon (the value you actually read at a glance), and the **stack count** in the corner.

Built because nobody really does this outside of ElvUI's tank module, and ElvUI is overkill if you just want a focused, lightweight tool.

Runs on both **WoW 12.0 Midnight (retail)** and **Mists of Pandaria Classic 5.5** from the same install.

## Features

- **Tank auto-detection** via group role AND `/maintank`, plus a force-include list for unassigned tanks
- **Boss-cast debuff filter** using Blizzard's secret-safe RAID filter — picks up M+/dungeon debuffs that older filters miss — with per-spell whitelist / blacklist
- **Big yellow timer** centered on each icon, **stack count** in the corner, both fully positionable + sizable
- **Compact mode** (default): class icon + auras only, perfect when your raid frames already show health
- **Display presets** (Full / Compact / Minimal) — applying one clones your profile non-destructively
- **Health, power and absorb bars** with LibSharedMedia textures, class / reaction / static color modes
- **Per-character profiles** with import / export (base64-encoded)
- **Modern responsive options panel** with collapsible sections, per-section reset, search bar, resize grip, saved size/position
- **Sister-addon side tabs** — one-click switch to BossWatch / SplitWatch when they're installed
- **Movable + lockable** mover with snap-to-edge and screen clamping
- **Minimap button** + LibDataBroker launcher (auto-shows in Titan Panel / ChocolateBar)
- **Visibility scope**: show only in raid, any group, or always
- **Test mode** (1 to 8 fake tanks with animated debuffs and shifting stacks)
- **9 languages**: French, English, German, Spanish, Italian, Brazilian Portuguese, Russian, Korean, Simplified & Traditional Chinese

## Installation

- **CurseForge** (recommended): https://www.curseforge.com/wow/addons/tankwatch
- **Wago.io**: https://addons.wago.io/addons/tankwatch
- **Manual**: drop `TankWatch/` into `World of Warcraft/_retail_/Interface/AddOns/` (or `_classic_/` for MoP Classic), `/reload`.

## Slash commands

| Command | Description |
|---|---|
| `/tankw` | Open the options panel |
| `/tankw mover` | Toggle the green-overlay drag handle |
| `/tankw test N` | Simulate N tanks (0 to 8) with fake debuffs |
| `/tankw reset` | Wipe all settings and reload the UI |
| `/tankw debug` | Print roster role / maintank info |
| `/tankw auradebug` | Print every HARMFUL aura on each tank unit |
| `/tankwatch` | Long alias for `/tankw` |

## Sister addons

TankWatch is part of the **watch family** — focused, lightweight WoW tools that play nice together:

- [**BossWatch**](https://www.curseforge.com/wow/addons/bosswatch) — customizable boss target frames
- [**SplitWatch**](https://www.curseforge.com/wow/addons/splitwatch) — automated raid subgroup balancing

When two or more are installed, side tabs appear on the options panel's left edge to switch between them with one click.

## Bundled libraries

LibStub · CallbackHandler-1.0 · LibSharedMedia-3.0 · LibDataBroker-1.1

## Support

- **Bugs / suggestions**: [GitHub Issues](https://github.com/Timikana/TankWatch/issues) · [Discord](https://discord.gg/uFmxwexQ4P)
- **Source**: [github.com/Timikana/TankWatch](https://github.com/Timikana/TankWatch)

## License

[MIT](LICENSE)
