# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
make build    # Build release binary
make bundle   # Create KeyGlow.app bundle
make run      # Build and run in release mode
make install  # Bundle, install to /Applications, and launch
make clean    # Clean build artifacts and app bundle
```

For debug builds: `swift build` then `.build/debug/KeyGlow`

There are no automated tests in this project.

## Architecture

KeyGlow is a macOS menu bar app (no Dock icon) that auto-toggles an Elgato Key Light based on camera activity. It uses only Apple system frameworks — no external dependencies.

**Entry point**: `main.swift` creates an NSApplication with `.accessory` activation policy (menu bar only), then delegates to `AppDelegate`.

**Four main components:**

- **`AppDelegate`** — orchestrates everything. Owns NSStatusItem, holds all app state (`lightOn`, `brightness`, `temperature`, `autoMode`, `cameraActive`), and calls `rebuildMenu()` on every state change.

- **`CameraMonitor`** — detects camera activity by spawning `/usr/bin/log stream` and parsing lines for `com.apple.UVCExtension` "Start Stream" / "Stop Stream" events. Calls an `onChange` closure on the main thread.

- **`KeyLightService`** — discovers the Key Light via CFHost DNS resolution (`elgato-key-light.local`), then controls it via HTTP on port 9123 (Elgato's API). Temperature is stored internally in API units (143–344) and converted to/from Kelvin (2900K–7000K) for display.

- **UI components** (`SliderMenuItem`, `GradientSlider`) — custom NSView/NSSlider subclasses for gradient-colored sliders with editable text fields in the menu.

**Key flows:**
- Discovery and initial state fetch run on a background `DispatchQueue`, then dispatch back to main thread to build the menu.
- Camera events → `AppDelegate.cameraDidChange()` → if autoMode ON, calls `KeyLightService.setLight()`.
- All slider/toggle interactions call `KeyLightService.setLight()` directly and update local state.

## App Bundle Structure

The `make bundle` target manually assembles `KeyGlow.app/` by copying the release binary and resources (Info.plist, AppIcon.icns, icon-16@2x.png) into the correct bundle layout. `make install` quits any running instance before copying to `/Applications/`.
