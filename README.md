# DisplayToggle

Turn external displays off and back on from the macOS menu bar without unplugging cables. DisplayToggle keeps displays it turned off in the menu and tries to preserve the resolution, refresh rate, and arrangement of the other displays.

## Install from source

Requires macOS 13 or later and a Swift toolchain from Xcode or the Xcode Command Line Tools.

```sh
git clone https://github.com/kikyung/DisplayToggle.git
cd DisplayToggle
./build.sh
open -R DisplayToggle.app
```

Finder selects the built app. Drag it to **Applications**, then open it. Click the display icon in the menu bar to get started. The app runs without a Dock icon.

The build script signs the local bundle ad hoc. Bundles downloaded from another machine may be blocked by Gatekeeper because they have not been notarized.

## Use DisplayToggle

| Menu item | Action |
| --- | --- |
| Display name | Toggle the display. A checkmark means it is on. |
| Enable All | Try to turn on every display that DisplayToggle turned off. |
| Quit | Try to turn those displays back on before exiting. |

The menu follows the system language when a translation is available and falls back to English.

### Display recovery

- DisplayToggle checks that another screen is active both when it builds the menu and immediately before it turns a screen off. A built-in screen with the lid closed does not count as active.
- If a configuration change leaves no active screens, DisplayToggle tries to re-enable the displays it turned off. It also tries to recover those displays when it starts.
- If a display is unavailable, reconnect it and choose **Enable All**. Failed attempts stay eligible for recovery.

## Compatibility

DisplayToggle uses a private CoreGraphics function. macOS updates can change or remove it. If the function is unavailable, the menu disables display toggling. This private API also prevents distribution through the Mac App Store.

Some displays disappear from the macOS online list when turned off. DisplayToggle saves the information needed to recover them within the current login session before turning them off. If it cannot save that information, it leaves the display on.

The app stores display names, UUIDs, layout information, and its recovery list locally in `~/Library/Application Support/DisplayToggle/displays.json`.

## Develop

```sh
swift test
./build.sh
./DisplayToggle.app/Contents/MacOS/DisplayToggle --list
```

`--list` reports available displays and their active state without changing the configuration. The tests use a fake display backend. Check screen toggling and layout restoration manually on the hardware you support.

- `Sources/DisplayToggle` contains the AppKit menu and localization code.
- `Sources/DisplayToggleCore` contains the display backend, safety rules, and recovery logic.
- `Resources` contains the menu translations. To add a language, copy `en.lproj` to a new language folder, translate the values, and keep the keys and format placeholders. Run `swift test` to check parity and `./build.sh` to bundle the translations.

See the [security policy](SECURITY.md) for vulnerability reporting and the [MIT license](LICENSE) for reuse terms.
