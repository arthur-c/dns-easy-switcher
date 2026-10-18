# DNS Easy Switcher 1.1.0

First release of the [arthur-c fork](https://github.com/arthur-c/dns-easy-switcher), based on the original project by [Gregory Linford](https://github.com/glinford/dns-easy-switcher).

- Add an optional **Launch at Login** setting using macOS login items, with approval guidance and synchronization with System Settings.
- Fix disappearing custom DNS profiles by moving the SwiftData database into an application-specific directory. The previous shared database could also be migrated by `icloudmailagent`.
- Automatically import remaining custom profiles and the active selection from the legacy database, including committed data in its SQLite write-ahead log, without modifying the source database.
- Report storage failures instead of silently using a temporary in-memory database. Failed profile saves keep the editor open for retry.
- Explicitly save the selected DNS profile and add seven persistence regression checks.
- Build universal Intel and Apple Silicon applications with GitHub Actions and publish DMG, ZIP, and SHA-256 checksums on version tags.

## Installation

Requires **macOS 14 or later**. Download the DMG or ZIP from this release, quit the previous app, and copy **DNS Easy Switcher.app** into **Applications**.

These builds use an **ad-hoc signature**; they are not signed with an Apple Developer ID or notarized. If macOS blocks the first launch, follow Apple's [Open Anyway instructions](https://support.apple.com/en-us/102445) in **System Settings → Privacy & Security**.

The upstream Homebrew cask installs the original application, so use this fork's release files to receive these fixes. Profiles already deleted from the legacy shared database cannot be recovered automatically.
