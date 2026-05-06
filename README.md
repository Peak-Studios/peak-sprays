# Peak Sprays

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.2.0-blue.svg)](version.json)
[![Discord](https://img.shields.io/badge/Discord-Peak_Studios-7289DA.svg)](https://discord.gg/gAqXUaVEMn)

Peak Sprays is a premium open-source FiveM resource for persistent in-world spray painting. Players select a wall area, paint on a DUI canvas, and the finished spray is saved to SQL and rendered back into the world for nearby players.

![Peak Sprays preview](docs/spray-preview.gif)

## Features

- Persistent spray paintings stored in SQL
- DUI-based in-world canvas rendering
- Paint, erase, undo, redo, brush sizing, color presets, and optional color picker
- Live preview while players are actively painting
- Admin panel for listing, previewing, teleporting to, and deleting sprays
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
3. Add the inventory items from [install](install) if you use item-based spray painting.
4. Configure [shared/config.lua](shared/config.lua) and [server/server-config.lua](server/server-config.lua).
5. Ensure dependencies before this resource:

```cfg
ensure ox_lib
ensure oxmysql
ensure peak-sprays
```

## Commands

- `/spraypaint` starts spray placement when `Config.UseCommand` is enabled.
- `/erasepaint` starts erase mode when `Config.UseCommand` is enabled.
- `/sprayadmin` opens the admin panel for permitted staff.

## Configuration

- **[shared/config.lua](shared/config.lua)**: The main, simplified config for non-coders. Use this for basic framework, item, and command settings.
- **[shared/internal_config.lua](shared/internal_config.lua)**: Advanced technical settings (DUI limits, render distances, brush presets, animations).
- **[client/custom.lua](client/custom.lua)**: Client-side hooks for permissions, notifications, progress bars, and targets.
- **[server/custom.lua](server/custom.lua)**: Server-side hooks for money overrides and lifecycle events.
- **[server/server-config.lua](server/server-config.lua)**: Sensitive server-only values such as Discord webhooks.

## Publishing Notes

- Do not publish live webhook URLs or credentials.
- Build the NUI before release with `npm run build` from the `ui` folder.
- Include `ui/dist`, `install`, `client`, `server`, `shared`, `fxmanifest.lua`, and this README in release archives.
- Do not include `ui/node_modules` in release archives.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before opening issues or pull requests.
