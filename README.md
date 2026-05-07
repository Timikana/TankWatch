<div align="center">

  # TankWatch

  **See every tank in your group, with the boss debuffs that actually matter.**

  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
  ![WoW Version](https://img.shields.io/badge/WoW-12.0%20Midnight-blue)

</div>

---

## What it does

TankWatch detects every tank in your party or raid (anyone with the **Tank** role assigned) and shows them as a clean stack of frames with health bars and the **boss-cast debuffs** stacking on them — with the **stack count rendered big** in the middle of each icon, because that's what tanks actually need to read at a glance.

Originally inspired by the fact that nobody really does this outside of ElvUI's tank module.

## Features

- Auto-detection of all tanks in party / raid via `UnitGroupRolesAssigned`
- Per-tank frame: HP bar (class-colored), name, health text
- **Boss-cast debuffs only** — no DoT noise, no healer-debuff clutter
- **Big, prominent stack count** in the icon center (the whole point)
- Cooldown swipe + small timer below each icon
- Combat-safe layout (uses secure unit buttons)
- LSM-powered textures and fonts
- Test mode (1 to 8 fake tanks with sample debuffs)
- French + English localization

## Installation

Manual: drop `TankWatch/` into `World of Warcraft/_retail_/Interface/AddOns/`, restart WoW.

## Slash commands

| Command | Description |
|---|---|
| `/tw mover` | Toggle the green-overlay drag handle |
| `/tw test N` | Simulate N tanks (0 to 8) with fake debuffs |
| `/tw reset` | Wipe all settings and reload the UI |

## Bundled libraries

LibStub, CallbackHandler-1.0, LibSharedMedia-3.0

## License

[MIT](LICENSE)
