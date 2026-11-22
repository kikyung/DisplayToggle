# DisplayToggle

A small macOS menu bar app that turns each external display on and off individually,
the same as unplugging its cable. No Dock icon, no windows.

## Features

- One menu item per physical display, with a switch to turn it off or on.
- Turned-off displays stay in the list so you can turn them back on.
- Other displays keep their resolution and arrangement when one is toggled.
- Safety guards: the last active display cannot be turned off, and displays are
  turned back on automatically at launch, on quit, or when no active display is left.

## Build

```sh
./build.sh          # creates DisplayToggle.app (ad-hoc signed)
swift test          # runs the unit tests
```

Requires macOS 13 or later and the Swift toolchain. No external dependencies.

## Install

The app is not notarized. After downloading, remove the quarantine attribute:

```sh
xattr -dr com.apple.quarantine DisplayToggle.app
```

## Notes

DisplayToggle uses the private CoreGraphics function `CGSConfigureDisplayEnabled`,
so it cannot be distributed on the Mac App Store and may break in future macOS releases.
If the symbol is missing, toggling is disabled and the menu says so.

Design and plan: `docs/superpowers/`.

## License

MIT
