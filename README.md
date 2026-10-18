# DNS Easy Switcher

A macOS menu bar app for switching DNS providers and managing custom DNS profiles.

This fork is maintained at [arthur-c/dns-easy-switcher](https://github.com/arthur-c/dns-easy-switcher), based on [Gregory Linford's original project](https://github.com/glinford/dns-easy-switcher).

[![Latest release](https://img.shields.io/github/v/release/arthur-c/dns-easy-switcher)](https://github.com/arthur-c/dns-easy-switcher/releases/latest)
[![Build and Release](https://github.com/arthur-c/dns-easy-switcher/actions/workflows/build-release.yml/badge.svg)](https://github.com/arthur-c/dns-easy-switcher/actions/workflows/build-release.yml)
[![Downloads](https://img.shields.io/github/downloads/arthur-c/dns-easy-switcher/total)](https://github.com/arthur-c/dns-easy-switcher/releases)

![Screenshot of DNS Easy Switcher](screenshot.png)

## Features

- Switch between Cloudflare, Quad9, AdGuard, and GetFlix DNS providers.
- Add, edit, and delete custom DNS profiles, with IPv4 and IPv6 support.
- Restore DHCP-provided DNS with **Disable DNS Overrides**.
- Compare server latency and flush the DNS cache.
- Authenticate DNS changes, with Touch ID where available.
- Launch automatically when you sign in to macOS.
- Keep profiles and selection settings between app launches.

## Changes in 1.1.0

- **Launch at Login:** enable or disable automatic startup from the menu, with macOS approval status and a shortcut to Login Items settings.
- **Custom DNS profiles no longer share a database with unrelated apps.** Settings now use a dedicated application directory, preventing another app's database migration from deleting saved DNS profiles.
- **Existing profiles migrate automatically.** The first launch copies remaining DNS profiles and selection settings from the legacy database, including committed SQLite write-ahead log data, without changing the shared database. Profiles already deleted from that database cannot be recovered by the migration.
- **Storage failures are visible.** The app no longer silently falls back to temporary in-memory storage, and an unsuccessful profile save keeps the editor open for a retry.
- **GitHub Actions builds and releases:** downloadable universal macOS builds are published from this fork.

## Installation

Requires **macOS 14 Sonoma or later**. Release builds contain both **Apple Silicon (arm64)** and **Intel (x86_64)** code.

1. Download the DMG or ZIP from this fork's [latest release](https://github.com/arthur-c/dns-easy-switcher/releases/latest).
2. Open the DMG and drag **DNS Easy Switcher** into **Applications**, or extract the ZIP and move the app there.
3. Open **DNS Easy Switcher** from Applications. Its controls appear in the menu bar.

Release archives include SHA-256 checksums. These builds are ad-hoc signed; they are **not signed with an Apple Developer ID or notarized by Apple**.

### First launch

macOS may block the downloaded app because its developer cannot be verified. If you trust this release, try opening it once, then go to **System Settings → Privacy & Security → Open Anyway** and confirm. See [Apple's instructions for opening downloaded apps](https://support.apple.com/en-us/102445).

Changing DNS settings requires administrator privileges. Touch ID is optional and depends on your Mac's authentication support.

### Launch at login

Open the app's menu and enable **Launch at Login**. Disable the same option to stop automatic launches.

If macOS requests approval, choose **Open Login Items Settings…** and allow DNS Easy Switcher in System Settings. The menu also reflects changes made directly in System Settings. Install the app in Applications before enabling this option.

## Building from source

Use a Mac with Xcode 15 or later installed and selected as the active developer directory.

```bash
git clone https://github.com/arthur-c/dns-easy-switcher.git
cd dns-easy-switcher
bash scripts/build-release.sh
```

The script builds a universal app and packages a DMG, a ZIP, and `SHA256SUMS` in `.build/dist`. It uses ad-hoc signing and does not require the original developer's signing certificate or team membership. You can also open `DNS Easy Switcher.xcodeproj` in Xcode to inspect or develop the app.

Run the persistence regression checks on macOS:

```bash
bash Tests/run-persistence-tests.sh
```

## Automated builds and releases

The [Build and Release workflow](https://github.com/arthur-c/dns-easy-switcher/actions/workflows/build-release.yml) runs the persistence checks and uploads universal build artifacts on pushes to `main`, pull requests targeting `main`, and manual runs.

Pushing a version tag such as `v1.1.0` publishes a [GitHub release in this fork](https://github.com/arthur-c/dns-easy-switcher/releases) containing a DMG, a ZIP, and `SHA256SUMS`. The tag version must match the project's `MARKETING_VERSION`. Branch, pull request, and manual builds do not publish releases.

## Storage and privacy

The app does not collect telemetry. Profiles and selection settings are stored locally at:

```text
~/Library/Application Support/com.linfordsoftware.dnseasyswitcher/default.store
```

The directory name retains the original bundle identifier for compatibility. On the first launch after upgrading, the app imports any remaining DNS data from the previous shared `~/Library/Application Support/default.store`. The legacy store is not modified or deleted. Once the dedicated store exists, later launches use it without importing again.

The DNS provider you select receives DNS queries; its own privacy policy applies.

## Contributing

Report problems or propose changes in [this fork's issues](https://github.com/arthur-c/dns-easy-switcher/issues) and [pull requests](https://github.com/arthur-c/dns-easy-switcher/pulls).

## License and acknowledgments

Licensed under the [MIT License](LICENSE), retaining the original copyright notice.

Thanks to [Gregory Linford](https://github.com/glinford) for the original app and to [Cloudflare](https://1.1.1.1), [Quad9](https://quad9.net), [AdGuard](https://adguard-dns.io/en/welcome.html), and [GetFlix](https://www.getflix.com.au/setup/dns-servers/) for their DNS services.
