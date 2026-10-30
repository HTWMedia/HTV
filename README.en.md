<div align="center">

# HTV · Live TV for Android

**Ad-free, works out of the box — a live TV player for Android phones, TVs and TV boxes**

[![Latest Version](https://img.shields.io/github/v/release/HTWMedia/HTV)](https://github.com/HTWMedia/HTV/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/HTWMedia/HTV/total?color=blue)](https://github.com/HTWMedia/HTV/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Android%204.4%2B-brightgreen)](https://github.com/HTWMedia/HTV/releases/latest)
[![Stars](https://img.shields.io/github/stars/HTWMedia/HTV?style=social)](https://github.com/HTWMedia/HTV)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](https://github.com/HTWMedia/HTV/blob/main/LICENSE)

[Download](https://github.com/HTWMedia/HTV/releases/latest) · [Features](#features) · [FAQ](#faq) · [Privacy](#privacy) · [中文](README.md)

</div>

---

![HTV live TV app social preview: ad-free, for Android phones, TVs and TV boxes](social-preview.png)

<p align="center">
  <img src="assets/images/screenshot-panel.jpg" width="49%" alt="Channel panel: groups, channel list, now playing and up next">
  <img src="assets/images/screenshot-settings.jpg" width="49%" alt="Settings panel: user profile, boot autostart, channel-flip direction, lean sources">
</p>

---

## About

HTV is an ad-free live-TV player for Android phones, smart TVs and TV boxes. The app is free, and it can use the built-in channels (CCTV, provincial satellite and local channels) or your own subscription sources. When a stream fails it automatically switches to the next available one — no manual fiddling. The UI adapts to both remote controls and touch screens.

- The app is free, no account and no ads
- Full built-in sources require sponsorship; custom live sources can be configured
- One APK for phones and TV boxes (Android 4.4+)
- Open source (Apache-2.0) — build and audit it yourself

> **Different from TVBox-style shells?** TVBox is an empty player: you have to find
> subscription sources and keep them working yourself. HTV works right after
> installation with built-in channels, and also accepts your own subscription source
> in the settings.

## Features

| Feature | Description |
| --- | --- |
| Live channels | CCTV, provincial satellite and local channels (full built-in sources require sponsorship) |
| Custom sources | Add your own m3u / txt subscription; leave the default source empty to load only your own |
| Automatic failover | On playback errors or no picture, switches to the next available source |
| Favorites | Long-press OK in the channel list to pin/remove favorites |
| Catch-up TV | Replay recent programs where the source supports it, with a diagnostics panel |
| EPG | Program guide loads automatically, covering the last 7 days |
| Layouts | Switch between grouped and list layouts; pick a specific source per channel |
| Remote-first | Full D-pad / number / OK / menu key navigation, plus touch gestures |
| Network | IPv4 and IPv6 supported |

## Download & install

1. Get the latest APK from [Releases](https://github.com/HTWMedia/HTV/releases/latest)
2. Install it on your phone, or sideload to your TV box via USB / file manager / ADB
3. Allow "install from unknown sources" once if prompted
4. On first launch, either activate the built-in sources or add your own under
   "Settings → Custom live source"

| File | Device |
| --- | --- |
| `HTV-<version>-armeabi-v7a.apk` | Most TV boxes and older phones (recommended; in-app update uses this) |
| `HTV-<version>.apk` | Universal build (larger, works on phones and boxes) |

`SHA256SUMS.txt` is attached to each release so you can verify the download.

## Built-in sources & custom sources

- **The app is free**: the player itself is free, ad-free and requires no account.
- **Built-in sources**: the bundled Chinese channels are a value-added service —
  **full built-in sources require sponsorship**. Without it, you can use your own
  subscription source instead.
- **Custom sources**: enter your own m3u / txt subscription under
  "Settings → Custom live source". With "Settings → Sources → Default source service"
  left empty, the app loads only your custom source.

## FAQ

### The spinner never stops / no picture

The app tries the next available source after a start timeout. If the whole channel
list fails to load, an on-screen hint appears — press OK to retry.

### A channel doesn't play

Open the info panel and switch to another source ("Source X/Y"). If no source works,
the channel's sources are likely dead — please report it in
[Discussions](https://github.com/HTWMedia/HTV/discussions), or switch to your own
subscription source.

### Does it work on an old TV box?

Android 4.4 and above is supported, including common carrier boxes and imported boxes.

### Is it really ad-free and account-free?

Yes. The player has no ads, needs no sign-up and collects no viewing behavior.
Built-in sources are a value-added service: full built-in sources require sponsorship,
or you can use your own subscription source.

### Do the built-in sources cost money?

The app itself is free. Built-in sources are maintained by the project, so **full
built-in sources require sponsorship** to cover maintenance. If you prefer a free
option, add your own subscription source under "Settings → Custom live source".

### What about catch-up?

Catch-up depends on whether the source provides it. Check "Settings → Catch-up diagnostics"
for the current channel.

### Can I add my own playlist?

Yes. Enter your own m3u / txt subscription under "Settings → Custom live source".
For private source setup and other custom work, contact the author via
[Discussions](https://github.com/HTWMedia/HTV/discussions).

## Privacy

HTV requires no account and contains no ad or analytics SDKs.

- **Network access** is used only to fetch the channel list and EPG, to check for
  updates on GitHub Releases, and to play the streams themselves.
- **Local data** (favorites, settings, history) stays on your device and is removed on uninstall.
- **Source code** is public in this repository.

## Build from source

```bash
git clone https://github.com/HTWMedia/HTV.git
cd HTV
flutter pub get
flutter build apk --release --split-per-abi
```

Requires Flutter 3.13+ and the Android SDK. The repository contains no stream URLs —
built-in channel data is fetched by the app at runtime, and can be replaced with your
own subscription endpoint under "Settings → Custom live source".

## Community

- [GitHub Discussions](https://github.com/HTWMedia/HTV/discussions) — bug reports,
  dead-channel reports, feature requests (searchable and indexed)
- New here? Start with the [download & feedback guide](https://github.com/HTWMedia/HTV/discussions/46)
  and the [dead-channel report guide](https://github.com/HTWMedia/HTV/discussions/47)
- Watch → Custom → Releases to get notified about new versions

## Support

The player itself is free, ad-free and requires no account. Built-in sources are
maintained by the project, so **full built-in sources require sponsorship**; without
it, you can add your own subscription source under "Settings → Custom live source"
at no cost.

If HTV saves you time, voluntary sponsorship is welcome:

> Sponsorship supports project maintenance, and activating the built-in sources is
> the corresponding benefit; the free use of the player itself is unchanged.

## Acknowledgements

[my_tv](https://github.com/yaoxieyoulei/my_tv "my_tv")

---

<sub>Live TV · IPTV player · m3u8 / HLS · Android TV · TV box · catch-up TV · EPG · [中文 README](README.md)</sub>
