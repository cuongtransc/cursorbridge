# CursorBridge

A macOS menu-bar app that decides where the cursor goes when it leaves a display, independent of the
arrangement in **System Settings › Displays**.

You drag your displays into a layout inside the app. Edges that touch in that layout are crossable, and
so are edges that face another display across a gap, which is what a grid of mixed-size monitors always
leaves. Where displays don't line up at all, you can link two edges directly. Window placement, the menu
bar and Mission Control keep using the macOS arrangement; only cursor travel is overridden.

## Features

- **Virtual layout editor** — drag displays around; edges snap together and shared edges show in green.
  A red dot tracks the live cursor so you can check the mapping.
- **Jump across gaps** — when an edge touches nothing, the cursor lands on the nearest display facing it,
  however wide the gap. Bridged gaps are shaded in the editor. Turn it off to make such edges walls.
- **Edge links** — click *Link Edges…*, then an edge on one display and an edge on another. The two edges
  are joined end to end: halfway along one lands halfway along the other. A link overrides the layout for
  that edge, so it also works for displays that don't face each other, or to wrap from the far right of the
  desk back to the far left.
- **Resolution or physical sizing** — in *Physical size* mode each display is sized in millimetres, so the
  cursor crosses at the same real-world height between a Retina laptop and a large external monitor.
- **Identify Displays** — flashes a numbered badge on each screen, matching the numbers in the editor
  (handy with several identical monitors).
- Layout is saved per display (keyed by the display's ColorSync UUID) and survives reconnects and reboots.
- Launch at login.

## Build and run

Requires macOS 14+ and the Swift 6 toolchain (Xcode or Command Line Tools).

```bash
make test      # unit tests for the routing logic
make run       # build build/CursorBridge.app and launch it
make install   # copy to ~/Applications and launch
```

On first launch macOS asks for **Accessibility** access (needed to watch and move the cursor). Grant it in
System Settings › Privacy & Security › Accessibility; routing starts automatically.

The app is ad-hoc signed by default, and macOS ties the Accessibility grant to the signature, so after a
rebuild you need to remove CursorBridge from the Accessibility list and add it again. To avoid that, sign
with a real certificate:

```bash
CODESIGN_IDENTITY="Apple Development: you@example.com" make install
```

## How it works

A session `CGEventTap` sees every mouse-move and drag event. For each one, `CursorRouter`:

1. finds the display the cursor was on before the move;
2. works out whether the move leaves that display — either macOS moved the cursor onto a native
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
