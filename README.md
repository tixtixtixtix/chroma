# Chroma

A native macOS color picker Droplet for [Droppy](https://getdroppy.app), built with SwiftUI and the public [DroppyKit SDK](https://getdroppy.app/docs/droppykit). Developed with Droppy Code by **tixtixtixtix**.

Select or enter a color, preview it, copy its HEX code, and pin it for later.

## Features

- Interactive saturation/brightness picker and hue strip in compact and expanded views.
- Editable HEX input supporting `#RRGGBB`, `RRGGBB`, `#RGB`, and `#RRGGBBAA`. Valid values normalize to uppercase; trailing `FF` alpha becomes six digits.
- Explicit HEX-only copying through the preview, Copy HEX button, Command-C, or a swatch context menu. Selecting a saved swatch loads it into the picker without copying.
- Persistent recent colors, with duplicates moved to the front. The default limit is 27 and can be adjusted from 1 to 300.
- Persistent pinned colors with optional names, drag reordering, and context-menu controls. Clearing history keeps pinned colors.
- Complementary and analogous color suggestions.
- Optional clipboard previews, checked when the picker opens or becomes active, without background polling or automatic clipboard replacement.
- Liquid Glass controls, native system typography, animated selection indicators, and copy confirmation.
- Preferences in Droppy’s app settings: history limit, HEX prefix, clipboard detection, copy confirmation, clear history, and reset preferences.

## Requirements

- macOS 14 or later.
- Droppy 15.3 or later, or [Droppy Playground](https://getdroppy.app/download/playground) for local development.
- To build: Xcode 26 with Swift 6.2 or later and the DroppyKit build tools.

The package pins DroppyKit **1.20.1** and declares a minimum public SDK API version of **1.12.0**. The official build produces a universal bundle for Apple silicon and Intel Macs.

## Build and install

Clone the project and the pinned SDK into sibling directories:

```sh
git clone https://github.com/tixtixtixtix/chroma.git
git clone --branch 1.20.1 --depth 1 https://gitlab.com/droppyformac1/droppykit.git
cd chroma
../droppykit/Scripts/droppykit build
../droppykit/Scripts/droppykit validate
```

The bundle is written to `.build/Chroma.droplet`. Use the official `droppykit build` command for distribution; a plain SwiftPM build does not provide the required host framework linkage.

In **Droppy**, open Settings → Droplet Store → Local droplets and add the bundle. Local unsigned builds require Droppy’s approval for that exact build and again on launch.

In **Droppy Playground**, drag the bundle into the Store installation area. Playground supports unsigned development bundles. Restart the host after updating an already-loaded bundle so it loads the new Swift code.

## Usage

Use the color plane and hue strip, or enter a HEX code in expanded view. Press Return to confirm manual input. Click a recent, pinned, or suggested color to load it into the picker. Click the compact preview or Copy HEX to copy the selected color.

Command-C copies the selected HEX when the picker has focus and a text field is not being edited. Text fields retain normal editing shortcuts.

Pin the selected color using the pin button. Right-click saved swatches to copy, pin or unpin, rename, reorder, or remove them. Drag pinned swatches to reorder them.

## Droppy capture integration

The eyedropper action reuses **Droppy’s capture color picker** through the public launcher command bridge. It is shown only when the host exposes that command.

Droppy’s capture picker copies its result itself, so this action is labelled “Pick & copy.” Chroma consumes the next valid HEX clipboard result during a short, event-driven capture session. The public SDK does not expose a color-result or cancellation callback. Manual entry and the inline picker leave the clipboard unchanged until an explicit copy action.

Playground and the SDK harness do not expose Droppy’s capture feature. Test this integration in Droppy; any capture permissions are managed by the host.

## Local storage and privacy

History, pinned colors, and preferences are stored locally through DroppyKit’s droplet-scoped preferences service. They survive app restarts and bundle updates. Clipboard detection can be disabled in app settings. Chroma requests no network capability and runs no clipboard polling service.

Older palette data remains preserved for compatibility, although palette management is no longer part of the interface.

## Development and verification

```sh
swift test
../droppykit/Scripts/droppykit run -- --shots ./shots --report ./shots/report.json
../droppykit/Scripts/droppykit run
```

Tests cover HEX parsing, copy behavior, input handling, history limits and deduplication, persistence, and native scroll layouts. The SDK harness renders each declared surface and reports activation or capability problems. Generated bundles, screenshots, editor configuration, temporary files, and credentials are excluded from Git.

The included icon and creator avatar are development placeholders. Droppy Store submission is a separate process and requires final creator artwork and the Store’s icon workflow.

See [CHANGELOG.md](CHANGELOG.md) for version history.

## License

[MIT License](LICENSE). Copyright © 2026 tixtixtixtix.
