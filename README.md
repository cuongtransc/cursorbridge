# CursorBridge

A macOS menu-bar app that decides where the cursor goes when it leaves a display, independent of the
arrangement in **System Settings › Displays**.

You drag your displays into a layout inside the app. Edges that touch in that layout are crossable, and
so are edges that face another display across a gap, which is what a grid of mixed-size monitors always
leaves. Where displays don't line up at all, you can link two edges directly. Window placement, the menu
bar and Mission Control keep using the macOS arrangement; only cursor travel is overridden.

## Features

- **Virtual layout editor**: drag displays around; edges snap together and shared edges show in green.
  A red dot tracks the live cursor so you can check the mapping.
- **Jump across gaps**: when an edge touches nothing, the cursor lands on the nearest display facing it,
  however wide the gap. Bridged gaps are shaded in the editor. Turn it off to make such edges walls.
- **Reach displays off to the side**: where nothing at all faces an edge (the outer parts of two monitors
  above a narrower laptop), the cursor goes to the nearest display in that direction and lands at its
  closest point. One switch covers every display; gaps left as walls stay walls. Off by default.
- **Edge links**: click *Link Edges…*, then an edge on one display and an edge on another. The two edges
  are joined end to end: halfway along one lands halfway along the other. A link overrides the layout for
  that edge, so it also works for displays that don't face each other, or to wrap from the far right of the
  desk back to the far left.
- **Resolution or physical sizing**: in *Physical size* mode each display is sized in millimetres, so the
  cursor crosses at the same real-world height between a Retina laptop and a large external monitor.
- **Identify Displays**: flashes a numbered badge on each screen, matching the numbers in the editor
  (handy with several identical monitors).
- Layout is saved per display (keyed by the display's ColorSync UUID) and survives reconnects and reboots.
- Launch at login.

## Build and run

Requires macOS 14+, the Swift 6 toolchain (Xcode or Command Line Tools) and [mise](https://mise.jdx.dev).

```bash
mise run setup         # once: local signing identity and the pre-commit hook
mise run test          # unit tests for the routing logic
mise run dev           # build build/CursorBridge.app and launch it
mise run app:install   # copy to ~/Applications and launch
mise run ci            # the gate the pre-commit hook runs
```

On first launch macOS asks for **Accessibility** access (needed to watch and move the cursor). Grant it in
System Settings › Privacy & Security › Accessibility; routing starts automatically.

macOS ties the Accessibility grant to the app's signature. `mise run setup` creates a self-signed
"CursorBridge Local Signing" identity in your login keychain; builds signed with it keep the grant across
rebuilds, and no other binary can claim it without that private key. The first build may ask for your
keychain password (choose *Always Allow*). To sign with another certificate:

```bash
CODESIGN_IDENTITY="Apple Development: you@example.com" mise run app:install
```

Without either, the build is ad-hoc signed and the grant has to be given again after every rebuild.

## How it works

A session `CGEventTap` sees every mouse-move and drag event. For each one, `CursorRouter`:

1. finds the display the cursor was on before the move;
2. works out whether the move leaves that display: either macOS moved the cursor onto a native
   neighbour, or pinned it against an edge while the event's delta still points outwards;
3. resolves the edge it left through: an edge link if there is one, otherwise the display touching that
   edge in the virtual layout, otherwise (with gap jumping) the nearest display facing it;
4. warps the cursor there with `CGWarpMouseCursorPosition` or, if nothing applies, holds it at the edge.

When the virtual layout matches the macOS arrangement, the router leaves every event alone.

## Layout

```
Sources/CursorBridgeCore   pure geometry: virtual layout, snapping, cursor routing (unit tested)
Sources/CursorBridge       the app: event tap, display discovery, SwiftUI editor, menu bar
scripts/                   build/test wrappers (handle Command Line Tools–only installs)
```

## Known limitations

- When you wall off an edge that macOS considers connected, the cursor can show on the neighbouring
  display for one frame before it is pulled back.
- Secure input (password fields, some login windows) suspends event taps, so routing pauses while it is
  active.

## License

Copyright © 2026 Siddhant Bhatnagar

CursorBridge is free software: you can redistribute it and/or modify it under the terms of the GNU
General Public License as published by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version. It is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; see [LICENSE](LICENSE) for the full terms.
