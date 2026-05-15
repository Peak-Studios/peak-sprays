# Peak Sprays

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.2.1-blue.svg)](version.json)
[![Discord](https://img.shields.io/badge/Discord-Peak_Studios-7289DA.svg)](https://dsc.gg/peakstudios)

Peak Sprays is a premium open-source FiveM resource for persistent in-world spray painting, text scenes, and signs. Players can paint on DUI canvases or place styled text/sign surfaces that are saved to SQL and rendered back into the world for nearby players.

> WIP notice: the gang laptop and turf systems are unfinished and still need full FXServer validation. See [docs/wip-turfs-testing.md](docs/wip-turfs-testing.md) before testing or deploying this branch.

![Peak Sprays preview](docs/spray-preview.gif)

## Features

- Persistent spray paintings, text scenes, and signs stored in SQL
- DUI-based in-world canvas rendering
- Paint, erase, undo, redo, brush sizing, color presets, and optional color picker
- Image-link sprays with allowlisted HTTPS hosts, placement, scale, rotate, undo, redo, and erase support
- Scene/sign editor with fonts, colors, backgrounds, visibility modes, expiry, and live placement preview
- Live preview while players are actively painting
- Admin panel for listing, previewing, teleporting to, and deleting sprays, text scenes, and signs
- Gang laptop with dashboard, members, turf map, mark editor, and activity tabs
- Spray-centered turf zones with ownership, discovered spray tracking, and contested turf states
- Framework bridge for QBCore, Qbox, ESX, OX Core, vRP, and standalone setups
- Usable item and command-based flows
- Editable custom hooks for permissions, notifications, economy, and server integrations
- Discord logging support with server-side webhook configuration

## Dependencies

- `ox_lib`
- `oxmysql`
- A supported framework and inventory if you want item-based usage

## Installation

### 🤖 AI-First Setup (Recommended)
If you are using an AI coding assistant (like Claude, ChatGPT, or Cursor), you can set up this resource in seconds:
1. Open [PROMPT.md](PROMPT.md).
2. Copy the content and paste it into your AI assistant.
3. Follow its instructions to automatically configure the framework, inventory, and items for your server.

### Manual Setup
1. Place this resource in your server resources folder as `peak-sprays`.
2. Import [install/install.sql](install/install.sql) into your database.
3. Import [install/install_gangs.sql](install/install_gangs.sql) if you are testing gang laptop or turf features.
4. Add the inventory items from [install](install) if you use item-based spray painting.
5. Configure [shared/config.lua](shared/config.lua) and [server/server-config.lua](server/server-config.lua).
6. Ensure dependencies before this resource:

```cfg
ensure ox_lib
ensure oxmysql
ensure peak-sprays
```

## Commands

- `/spraypaint` starts spray placement when `Config.UseCommand` is enabled.
- `/erasepaint` starts erase mode when `Config.UseCommand` is enabled.
- `/scene [text]` opens the text scene editor when `Config.SceneUseCommand` is enabled.
- `/sign [text]` opens the sign editor when `Config.SceneUseCommand` is enabled.
- `/hidescenes` toggles local text scene/sign visibility.
- `/deletescene` deletes the nearest owned text scene/sign, or any scene/sign for admins.
- `/sprayadmin` opens the admin panel for permitted staff.
- `/ganglaptop` opens the WIP gang laptop when `Config.GangLaptopCommand` is enabled.

## Configuration

- **[shared/config.lua](shared/config.lua)**: The main, simplified config for non-coders. Use this for basic framework, item, and command settings.
- **[shared/internal_config.lua](shared/internal_config.lua)**: Advanced technical settings (DUI limits, render distances, brush presets, animations).
- **[client/custom.lua](client/custom.lua)**: Client-side hooks for permissions, notifications, progress bars, and targets.
- **[server/custom.lua](server/custom.lua)**: Server-side hooks for money overrides and lifecycle events.
- **[server/server-config.lua](server/server-config.lua)**: Sensitive server-only values such as Discord webhooks.

### Image Sprays

Image sprays are enabled with `Config.ImageSpraysEnabled` in [shared/internal_config.lua](shared/internal_config.lua). Players can paste an HTTPS image URL while painting, place it on the selected canvas, scale and rotate it, then save it as part of the spray.

Remote images are restricted by `Config.ImageAllowedHosts`. Keep this list tight and only include hosts you trust. Images are stored as URLs in `stroke_data`, so a spray can render blank later if the remote file is deleted, moved, blocked by CORS, or blocked by the player's client.

### Gang Laptop and Turf (WIP)

The gang laptop and turf map are experimental in this branch. The laptop is packaged in the existing NUI build and uses a transparent, non-fullscreen shell so players can keep the game visible around it.

Key settings live in [shared/internal_config.lua](shared/internal_config.lua):

- `Config.InfluenceRadius`: default owned turf radius, currently `90.0`.
- `Config.ContestedInfluenceRadius`: default contested turf display radius, currently `50.0`.
- `Config.PlacementDistance`: minimum same-gang spray spacing, currently `75.0`.
- `Config.ContestDuration`: required contest hold time.
- `Config.DailyLimitType` and `Config.DailyLimitCount`: gang spray limit behavior.
- `Config.GangLaptopCommand`: command name for the laptop.
- `Config.GangSprayItem`: gang spray inventory item name.

The territory map uses the built `ui/dist/images/territory_map.png` asset. The manifest packages it through the existing `ui/dist/**/*` file rule.

Before treating this as ready, complete the checklist in [docs/wip-turfs-testing.md](docs/wip-turfs-testing.md).

## Publishing Notes

- Do not publish live webhook URLs or credentials.
- Build the NUI before release with `npm run build` from the `ui` folder.
- Include `ui/dist`, `install`, `client`, `server`, `shared`, `fxmanifest.lua`, and this README in release archives.
- Do not include `ui/node_modules` in release archives.
- Do not publish the WIP gang laptop and turf work as production-ready until the in-game test checklist passes.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before opening issues or pull requests.
