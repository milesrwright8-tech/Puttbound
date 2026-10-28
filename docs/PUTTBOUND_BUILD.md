# Puttbound delivery guide

## What is included

Puttbound is an original offline-first 3D mini-golf game authored in Godot 4.7.2. It is designed for landscape Android play and includes a browser preview for inspection. The runtime generates five themed worlds and 30 data-driven holes locally; it does not use a backend, account, network service, analytics, advertisements, or runtime asset downloads.

The implemented game includes:

- 30 catalogued holes across Sunny Park, Candy Kingdom, Neon Arcade, Pirate Cove, and Space Station.
- Reusable procedural course construction with walls, slopes, ramps, mazes, bumpers, moving gates, launch pads, paired teleport pads, water hazards, world-specific props, cup flags, and local-color ball variants.
- Rigid-body ball physics with friction/damping, gravity variation, bounce/collision surfaces, rolling, out-of-bounds recovery, hazard recovery, launch boosts, and a smooth follow camera.
- Touch and mouse drag/pull-back shot control with aiming guide and power meter; keyboard shortcuts for pause, restart, and a basic shot for desktop smoke checks.
- Campaign progression with local unlock state, per-hole best scores, par-relative medals, hole completion results, quick play, practice, course selection, and local pass-and-play for 2–4 players.
- Main menu, course selection, settings, credits, pause/restart flow, HUD, stroke/par/hole/turn information, beginner guide toggle, and local JSON save with temporary-file replacement.
- Bundled local WAV feedback cues for putt impact, cup entry, hazard reset, and UI feedback. No runtime audio download is needed.
- Puttbound-specific Web loading screen and Godot Web preview export.

## Validation evidence

These commands passed on the final source:

```text
npm run check
npm run check -- --pack
npm run build
npm run preview:build
```

The finite smoke check verifies that the active scene loads, creates a follow camera, exposes a 30-hole catalog, creates a physical ball and cup, and moves the ball after a released shot. Native title and first-hole renders were captured under the real renderer in `captures/`.

The verifier also reports that the visual-coverage roles remain unregistered in the Addon metadata. This is a metadata/evidence limitation, not a claim that the procedural course visuals are absent; the game’s course geometry and props are generated directly by the project runtime. The native captures are the concrete rendered evidence for title and first-hole presentation.

## Android APK status

The project contains an Android export preset in `export_presets.cfg`, but this sandbox does not contain Godot Android export templates, the Android SDK platform-tools/build-tools, or a configured Java SDK. The attempted command was:

```bash
godot --headless --path . --export-release "Android" dist/puttbound.apk
```

Godot stopped before generating an APK with missing-template and missing-SDK errors. Therefore **no APK is claimed or included from this environment**.

## Rebuild the Android APK

1. Install Godot 4.7.2 and the matching Android export templates.
2. Install Android SDK Platform Tools, an Android platform (API 33 or newer recommended), Build Tools, and a supported JDK.
3. In Godot Editor Settings, configure the Java SDK path and Android SDK path.
4. Open this project and confirm the `Android` preset is enabled. Keep the package name `com.puttbound.worldsinmotion`, arm64 enabled, and Internet/access-network permissions disabled.
5. Export with:

   ```bash
   godot --path . --export-release "Android" dist/puttbound.apk
   ```

6. Install with Android Studio, `adb install -r dist/puttbound.apk`, or copy the APK to an Android phone and allow installation from that file source.

The authored project is intended for Android API 23+ and should be tested on API 26+ arm64 devices for the recommended experience. A 4 GB RAM Android phone with a modern Adreno, Mali, or equivalent GPU is recommended.

## Known limitations

This is a substantial playable implementation, but it is not a claim that every requested production feature has been individually device-tested. The current source does not include a separate world-results screen, free-form player-name entry, a fully implemented undo history, or a user-facing graphics-quality selector. Procedural course variants are generated from a compact catalog rather than hand-authored scene files. The browser/Web preview is available; native Android packaging remains pending the missing Android export toolchain described above.
