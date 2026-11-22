# DisplayToggle

Turn each external display on or off from the macOS menu bar, as if you had unplugged its cable.

DisplayToggle lives in the menu bar only. It has no Dock icon and no windows.

## Features

- **One item per physical display.** Each connected display appears once, with a switch to turn it off or on.
- **Turned-off displays stay in the list**, so you can switch them back on without touching cables or monitor inputs.
- **Layout is preserved.** Before a change, the app records the resolution, refresh rate, and position of the other displays. If macOS changes them, the app restores them in one display configuration transaction.
- **Safety guards** keep you from ending up with no screen (see [Safety](#safety)).
- **Localized.** The menu follows the system language: English, Korean, Japanese, Simplified and Traditional Chinese, French, German, and Spanish. Other languages fall back to English.
- **No dependencies.** Plain Swift Package, AppKit, and CoreGraphics.

## Requirements

- macOS 13 or later
- A Swift toolchain (Xcode or Command Line Tools) to build from source

Developed and tested on macOS 27 with Apple silicon, using a MacBook with two external displays.

## Build and run

```sh
git clone git@github.com:kikyung/DisplayToggle.git
cd DisplayToggle
./build.sh
open DisplayToggle.app
```

`build.sh` builds a release binary and wraps it in `DisplayToggle.app` with `LSUIElement` set, so the app has no Dock icon. The bundle is ad-hoc signed, not notarized.

If you copy a prebuilt `.app` from another machine, macOS may refuse to open it. Remove the quarantine attribute:

```sh
xattr -dr com.apple.quarantine DisplayToggle.app
```

To list displays without changing anything, run the binary with `--list`:

```sh
.build/debug/DisplayToggle --list
```

## Usage

Click the display icon in the menu bar.

| Menu item | What it does |
|-----------|--------------|
| A display | Turns that display off if it is on, or on if it is off. A checkmark means it is on. |
| A display with a reason in parentheses | Cannot be turned off right now. The item is disabled. |
| Enable all | Turns on every display that this app turned off. |
| About | Shows the About panel, with links to this repository and to support the project. |
| Quit | Turns on every display that this app turned off, then quits. |

The menu is rebuilt each time you open it, so it always shows the current state.

## Safety

| Guard | Behavior |
|-------|----------|
| G1 | A display cannot be turned off if no other display would remain active. |
| G2 | G1 is checked when the menu opens and again right before the display is turned off. |
| G3 | If a display configuration change leaves zero active displays, the app turns on the displays it had turned off. |
| G4 | At launch, the app turns on any display it turned off in a previous session. "Off" lasts for one session. |
| G5 | The built-in display counts as active only when it is actually on. A closed lid is not counted. |

Example: you turn off display B, then switch display A's input to another computer. Mac loses A, so B would be the only screen. Because no display is left, G3 turns B back on.

## How it works

DisplayToggle calls the private CoreGraphics function `CGSConfigureDisplayEnabled`, inside a normal display configuration transaction. The symbol is looked up with `dlsym` at runtime. If it is missing, toggling is disabled and the menu says so.

Displays are identified by UUID, not by `CGDirectDisplayID`, because display IDs can change. The app stores the displays it has seen, and the ones it turned off, in `~/Library/Application Support/DisplayToggle/displays.json`. This is how a turned-off display stays in the menu.

```
MenuBarController ── DisplayController ── DisplayBackend (protocol)
                      │      │               └─ CoreGraphicsBackend
                      │      └─ SafetyGuard
                      └─ DisplayRegistry
ReconfigWatcher ── recovery on configuration changes (G3)
```

## Adding a language

1. Copy `Resources/en.lproj` to `Resources/<language code>.lproj` (for example `it.lproj`).
2. Translate the values in `Localizable.strings`. Keep the keys and any `%@` placeholders.
3. Run `swift test`. It checks that every language has the same keys and placeholders as English.
4. Run `./build.sh`. The new language is added to the app bundle and `Info.plist` automatically.

## Limitations

- The app uses a private API. It cannot ship on the Mac App Store, and a future macOS release may change or remove the behavior.
- Hardware behavior (turning a display off and on, restoring layout) cannot be covered by automated tests, because the display really turns off. The logic around it is tested with a fake backend. Hardware checks are manual.
- Brightness, resolution picking, virtual displays, hotkeys, and automation rules are out of scope.

## Development

```sh
swift build      # debug build
swift test       # unit tests with a fake display backend
```

| Path | Contents |
|------|----------|
| `Sources/DisplayToggleCore` | Models, safety rules, registry, controller, CoreGraphics backend |
| `Sources/DisplayToggle` | Menu bar app (AppKit) |
| `Resources/*.lproj` | Localized menu strings |
| `Tests/DisplayToggleCoreTests` | Unit tests |
| `docs/superpowers` | Design spec and implementation plan |

Source code was written from scratch. The only technique shared with other display tools is the publicly documented idea of disabling a display through the private CoreGraphics call.

## Support

If DisplayToggle is useful to you, you can [buy me a coffee](https://buymeacoffee.com/kikyung).

## License

[MIT](LICENSE)
