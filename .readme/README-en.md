| 支持语言 | Support Language  |
|:--:|:--:|
| [中文](../README.md) | [English](README-en.md) |

<p align="center">
  <img src="../assets/images/copper.png" alt="Copper Launcher">
</p>

# Copper Launcher

A multi-platform game launcher for [Mindustry](https://github.com/Anuken/Mindustry), built with **Flutter**.

> [!WARNING]
> **Under active development**: features and UI are still changing fast. No stable release yet.

<p align="center">
  <img src="UI-demo.png" alt="Copper Launcher interface preview" width="900">
</p>

## Supported Platforms

| Platform | Status |
|:--|:--|
| **Windows / Linux / macOS** | Fully supported, all launcher features available |
| **Android** | Requires **CopperModLoader** to work properly |
| **iOS** | Not supported. Heavy platform restrictions, and Java mods cannot run there anyway |

## Features

### Version Management

- Manage multiple game versions side by side, with **isolated save data** per version
- The version list comes from the official GitHub repository, with a bundled snapshot so history stays browsable when the network fails
- Grouped by **era** (Modern / Classic / Legacy), with notes on what each era supports (e.g. whether mods work)
- Download a specific build, or preview builds (BE)
- Import / export resources (saves, maps, mods, blueprints); importing is still being finished
- View and export game crash logs
- Track play time and last launch time per version
- Generate launch scripts (`.bat` / `.sh`) so the game can start without the launcher

### Launching the Game

- Configure JVM arguments before launch, with **automatic heap allocation** (estimated from available memory and the size of enabled mods)
- Manage multiple Java runtimes, download from Adoptium when a runtime is missing, and pick a Java version compatible with each game version (Java 8 is safest for old versions)
- Override in-game settings and the multiplayer username
- Move the launcher into the **system tray** while playing, then restore the window when the game exits (desktop)
- Single-instance: launching again brings the existing window back

### Mod Management

- Browse and download mods: the list comes from the official MindustryMods repository, with jar / zip downloads; for non-Java mods the launcher can fetch source and name it automatically
- Enable / disable mods by writing both the game settings and the file extension, so the official loader never picks up disabled mods
- Batch operations: multi-select, drag-to-select, search and category filters
- Drag and drop files to import on desktop
- Dedicated support for **CopperModLoader**

### Network & Downloads

- Unified network layer: automatic user agent, GitHub API token injection, chunked multi-threaded downloads with resume, and speed limits
- **GitHub mirror acceleration**: direct connection first, automatic fallback to mirrors on network errors, with node speed tests and custom nodes
- Three proxy modes: follow system / custom / disabled

### Interface

- Custom UI style (not strictly Material 3), with its own press-rebound, overlay, dropdown and slide-menu components
- Multiple accent colors, plus dark / light / follow-system themes
- Background task drawer for download and extraction progress, with task logs

~~And an extremely good-looking UI with smooth animations~~

## Building from Source

Requires **Flutter** (Dart SDK `^3.11.5`). Desktop targets can only be built on their own host OS.

```bash
flutter pub get
flutter run -d windows     # dev run (use -d linux / -d macos instead)
flutter test               # tests
flutter analyze            # static analysis, aiming for 0 errors
```

For release builds and packaging, use `tool/build_release.dart` — interactively, or with arguments:

```bash
dart tool/build_release.dart --version 0.0.2 --channel alpha --bump --platform windows,android --package both
```

- Targets are multi-select: `windows` / `android` / `linux` / `macos`. The interactive prompt only lists targets the current host can build; targets passed on the command line that do not match the host are skipped with a notice
- Packaging follows the platform: Zip / Setup on Windows, tar.gz on Linux, dmg on macOS. Artifacts land in `build/dist/`

Some data ships outside the launcher (version snapshot, GitHub mirror nodes, per-version settings adapter tables). It lives in the `remote/` directory of this repository and is fetched at startup to overwrite the bundled copies.

## Acknowledgements

This project mainly draws on the design of third-party Minecraft launchers:

1. **PCL2**: UI design and page flow
2. **LauncherX**: background task system
3. **HMCL**: parts of the backend logic

## Help Wanted

The **blueprint feature** still lacks a data source: it needs a site or API that serves blueprint lists / search / downloads (the way the official repository serves mods and mindustry.top serves maps).

The blueprint page is already built, but it has stayed closed because there is no usable site behind it. If you run such a site, or know a good one, please open an issue.
