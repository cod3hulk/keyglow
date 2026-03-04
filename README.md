# KeyGlow

A lightweight macOS menu bar app that automatically turns your **Elgato Key Light** on and off based on your camera activity. When your camera starts streaming, the light turns on. When the stream stops, it turns off.

No background script, no terminal window — just a native menu bar icon.

## How it works

- Monitors macOS system logs for UVC camera events (`Start Stream` / `Stop Stream`)
- Discovers the Key Light on the local network by resolving the hostname `elgato-key-light` (the OS appends your configured DNS search domain, e.g. `elgato-key-light.fritz.box`). Falls back to `elgato-key-light.local` via Bonjour/mDNS
- Controls the light via the [Elgato Lights HTTP API](https://github.com/adamesch/elgato-key-light-api) (`PUT /elgato/lights`)
- Runs as a menu bar-only app (no Dock icon)

## Menu bar

| Item | Description |
|---|---|
| `Key Light: <ip>` | Resolved IP address, or "Not Found" |
| `Camera: Active / Inactive` | Current camera state |
| `Light: ON / OFF` | Current light state |
| `Auto Mode: ON ✓ / OFF` | Toggle automatic on/off with camera |
| `Turn Light On / Off` | Manual override |
| `Rediscover Key Light` | Re-run DNS discovery |
| `Quit` | Exit the app |

## Requirements

- macOS (tested on macOS Sequoia)
- [Rust](https://rustup.rs) + Cargo
- Node.js + npm
- An Elgato Key Light connected to the same local network

## Development

Install dependencies and start in dev mode:

```sh
npm install
npm run tauri dev
```

The Rust backend compiles and launches the app. Changes to the frontend (TypeScript/HTML) hot-reload automatically. Rust changes require a recompile.

## Build

Produce a release `.app` bundle:

```sh
npm run tauri build
```

The output is placed in `src-tauri/target/release/bundle/macos/KeyGlow.app`. You can move it to `/Applications` like any other macOS app.

## Tech stack

| Layer | Technology |
|---|---|
| App framework | [Tauri v2](https://tauri.app) |
| Backend | Rust |
| Frontend | TypeScript + Vite (minimal — tray-only app) |
| Light control | HTTP via `reqwest` (blocking) |
| Camera detection | `log stream` subprocess (UVC extension events) |
| Host discovery | `std::net::ToSocketAddrs` (system DNS + mDNS) |
