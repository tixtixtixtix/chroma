# Changelog

## [1.0.10] - 2026-10-10

- Keep saved-color hosting stable so insertion and reordering animations survive native scrolling.
- Animate the suggestion label and glass width together with a SwiftUI label over the native menu.
- Restore selected-color dots on saved swatches, including the compact column.
- Fix the compact copy/check confirmation badge to a centered, constant size.

## [1.0.9] - 2026-10-10

- Vertical quick swatches beside the compact selector, with a wider paired layout and square preview.
- Hover copy symbol smoothly changes to a confirmation checkmark on the compact preview.
- All swatches select without copying; Copy HEX remains available explicitly.
- Shared swatch motion, solid color tiles without checkerboard fringes, and no pressed-opacity dimming.
- Collapse symbol, animated suggestion-menu width, native system typography, and no selector focus ring.

## [1.0.8] - 2026-10-10

- Fit compact height to visible controls and swatches, removing empty row reservation.
- Measure the expanded header and saved content instead of reserving spare height.
- Tighten bottom padding while keeping suggestions scrollable.

## [1.0.7] - 2026-10-10

- Interactive compact picker with the copyable color preview on the left and HEX below it.
- Reuse the full saturation/brightness and hue controls in solo and paired shelf layouts.
- Publish saved-color changes once; use simple swatch fades and stable positions instead of blur/fold transitions.

## [1.0.6] - 2026-10-10

- Keep each swatch’s identity across grid rows so recent and pinned insertions and rearrangements animate continuously.
- Animate selection feedback on Recent swatches and apply list animation when the saved library changes.
- Remove the bottom fade and Pinned count; keep the native scrollbar.

## [1.0.5] - 2026-10-10

- Default to 27 recent colors, retain the adjustable limit, and use nine-column swatches without a recent count.
- Fit the expanded picker and saved-color area to content; fully measured rows and bottom padding keep suggestions reachable.
- Toggle between pin and unpin for the selected color.
- Compact view adds quick pinning, a larger HEX copy target, copy confirmation, and a selected-swatch indicator.
- Animate additions and repositioning in Recent, Pinned, and compact swatches.

## [1.0.4] - 2026-10-10

- Hide the capture eyedropper when the host does not provide it.
- Persistent native scrollbar and a bottom fade driven by actual scroll geometry.
- Remove palette sections and management menus; existing stored data is preserved.
- Copy icon changes to a green checkmark and shows the copied HEX code, using native symbol transitions.

## [1.0.3] - 2026-10-10

- Clock-style HEX value transitions when the field is not being edited.
- Quick gradient and color-preview blends, with slower marker movement.
- Visible saved-color scrollbar and a bottom fade while more content remains below.
- Removed the secondary color-panel and sRGB label row.
- Liquid Glass styling for the complementary/analogous menu.

## [1.0.2] - 2026-10-10

- Smoothly animated color and hue selection markers using Droppy’s motion presets.
- Native Liquid Glass HEX input with hover and focus feedback.

## [1.0.1] - 2026-10-10

- Recent swatches now select on click.
- Inline saturation/brightness picker with a hue strip.
- Preferences are available only in Droppy’s app settings.
- Fixed a copy action collision with NSObject.copy().

## [1.0.0] - 2026-10-10

- Editable HEX with instant preview, shorthand and trailing alpha.
- Native macOS visual selection and public command bridge to Droppy’s capture picker.
- HEX-only copy actions, confirmation, and keyboard handling.
- Persistent recent colors, pins, names, ordering, and named palettes.
- Complementary and analogous suggestions.
- Event-driven clipboard previews and native preferences.
