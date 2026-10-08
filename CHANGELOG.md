# Changelog

All notable changes to Pesty are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [1.3.0] - 2026-10-08

The v2 wave of features from @alvst (#80), each reviewed and landed with the
author's commits, plus everything merged since 1.2.0: undo for deletions, image
previews on cards, a real search field, a full clip context menu with an
editor, multi-select, retention limits and dragging clips out of Pesty.

### Added
- Image clips, and file clips that point at one image, show the picture edge
  to edge over a checkerboard; other file clips show the file's Finder icon,
  with a "File not found" caption when the file is gone. Decoding happens off
  the main thread behind a bounded cache. (#96, #102)
- Command-Z puts a deleted clip, or a whole bulk delete, back where it was for five
  minutes, and an Undo button sits in the bar while something is restorable.
  Hold Option while deleting to skip it for that deletion, or turn on "Delete
  permanently" in Settings. The undo stack is in memory only: nothing deleted
  is written back to disk or synced. (#88)
- The search indicator is a real, editable field. Return pastes the selected
  clip, Command-1 to Command-9 still quick-paste, and the arrow keys move the selection
  while typing. (#85, #101)
- Command-C copies the selected clip and moves it to the front of history. (#82)
- Paste as Clean Formatting or as Markdown from the card menu. (#93)
- Command-Left and Command-Right switch between History and Pinboards. (#83)
- Clip color themes (Default, Vibrant, Accent Shades) and a choice of where the
  selected clip sits in the strip. (#94)
- History can be limited by clip count or by age. The age limit is a slider
  with named presets from 1 Day to Forever, applied when the drag ends and
  confirmed when it would remove clips. Pruning is local and never removes
  clips from other devices. (#76, #89)
- An optional live-resize handle on the Paste Bar, off by default. (#87)
- "Play sound when copying from Pesty", separate from the paste sound. (#90)
- History's size on disk in Settings, covering history and pinboards. (#91)
- Real pixel dimensions for image clips and real paths for file clips in the
  card footer. (#95)
- "Promote pasted clips to the top of history", off by default. (#92)
- Icons on the bar's overflow menu. (#84)
- Double-click a Pinboard tab to rename it. (#103, #100)
- A full clip context menu: Paste to the target app, Paste as Plain Text, Copy,
  Edit in a rich-text editor with Writing Tools, Rename, Pin, Preview, Share
  and Delete. (#78)
- Multi-select: Command-click toggles a card, Shift-click extends the range, and
  deleting more than one clip asks first with the exact count. (#77)
- Drag clips out of Pesty into other apps or Finder: links as URLs, images as
  PNG, files as file URLs, rich text as RTF. (#73)
- The quick-paste and plain-text modifiers are configurable. (#71)
- A bare Backspace deletes the selected clip when no search is active, ignoring
  key repeat and a query that was just cleared. (#70)
- A preference to keep the bar open when clicking outside; a pinned bar no
  longer covers full-screen apps. (#74)
- Copies made through other clipboard tools attribute to the real origin app
  through the org.nspasteboard.source marker. (#72)
- The bar adopts Liquid Glass and the clip cards get a clearer visual
  hierarchy. (#14, #15)
- A standalone SwiftPM smoke test. (#79)

### Fixed
- A direct paste blocked by a missing Accessibility grant says so once in the
  toast instead of silently copying. (#92)
- The bulk-delete button no longer collapses to icon-only in narrow layouts.
  (#86)
- Copying a Pinboard clip back to history gives it its own identity, so sync
  cannot evict it. (#82)
- Editing a clip can no longer make CloudKit delete the clip that was just
  edited. (#78)
- The clip strip returns to its start each time the bar opens. (#69)
- Pesty shows the Paste Bar when it is reopened. (#68)
- Deleting is scoped to the collection on screen. (#67)
- The bar's key monitor is scoped to its own panel and the paste target is
  resolved from the app that was frontmost before the bar. (#66)
- Long search queries keep the newest typed text visible. (#75)
- The sync control is hidden in builds where sync is off. (#7)

[1.3.0]: https://github.com/momenbasel/pesty/releases/tag/v1.3.0

## [1.2.0] - 2026-08-11

Bug fixes for multi-monitor setups and a bar that could stop opening, plus a
per-app privacy filter. The Mac App Store build also gains iCloud sync.

### Added
- Privacy: exclude chosen apps from clipboard history. Nothing copied while an
  excluded app is frontmost is recorded. The list starts empty.
- Pause clipboard capture from the menu bar or with `⌘⇧P` while the bar is open,
  and open Settings with `⌘⇧S`.
- Preference to hide the menu bar icon. Opening Pesty again from Finder or
  Spotlight brings it back.
- Quit button in Settings, since the app has no application menu and `⌘Q` does
  not reach it.
- Mac App Store build only: history and pinboards sync across devices through
  CloudKit, including the iPhone app. The Homebrew and direct-download builds are
  unchanged - CloudKit needs an App Store provisioning profile.

### Fixed
- The Paste Bar could stop opening entirely until Pesty was relaunched. The bar's
  visibility was read from a window flag that only cleared inside an animation
  completion handler, and a dropped handler left the app convinced the bar was
  already up, so every hotkey press tried to hide it. Presentation state is now
  explicit and no longer depends on the animation. (#64)
- On multi-monitor setups the bar could appear on the wrong display and fly
  across the bezel. Screen selection now hit-tests the pointer properly, and the
  bar slides its content inside a parked panel rather than moving the window
  through the space between displays. (#63)
- The global hotkey could be lost for good if another app held the combination
  during login or a display change. Registration now retries and keeps the
  previous binding if the new one will not take.
- Sleep, wake, docking, and resolution changes no longer leave the bar stranded
  on a display that is gone.
- Building from source no longer resets the Accessibility permission on every
  build.

[1.2.0]: https://github.com/momenbasel/pesty/releases/tag/v1.2.0

## [1.1.0] - 2026-06-26

Visual overhaul to match Paste, plus iCloud sync.

### Added
- iCloud Drive sync (opt-in) for history and pinboards across your Macs.
- Live Accessibility permission status in Settings, with a Restart button.

### Changed
- Redesigned cards: per-source-app colored header band, app-icon tile, type
  label, verbose relative time, and a footer with character count + quick-paste
  number — a faithful match to Paste.
- Spring animations for selection, hover, and scrolling; taller default strip.
- Top bar now has a sync toggle, search indicator, a "Clipboard" tab, and a
  "…" overflow menu.

### Fixed
- Search input and keyboard navigation reliability.
- Removed the unnecessary Apple Events entitlement.

[1.1.0]: https://github.com/momenbasel/pesty/releases/tag/v1.1.0

## [1.0.0] - 2026-06-26

Initial public release.

### Added
- Slide-up clipboard strip with a global hotkey (default `⌘⇧V`).
- Color-coded cards for text, rich text, links, images, files, and colors, each
  showing source app, editable title, copy time, preview, and character count.
- Pinboards: named, color-tagged collections of saved clips.
- Instant search across the full history.
- Keyboard navigation: arrows to move, `return` to paste, `⌘1`–`⌘9` quick-paste,
  `⌘⌫` to delete, `esc` to close.
- Direct paste into the previously active app via synthesized `⌘V`.
- Privacy: ignores concealed (password-manager) clips.
- Menu-bar item, preferences window, configurable hotkey, launch at login.
- Universal binary (Apple Silicon + Intel), signed with Developer ID and
  notarized by Apple.

[1.0.0]: https://github.com/momenbasel/pesty/releases/tag/v1.0.0
