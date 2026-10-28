# ShipThis export handoff

This folder is a standard Godot 4 project. It contains `project.godot`, the source scenes/scripts, bundled audio, `export_presets.cfg`, and `shipthis.json`. ShipThis can build it in the cloud, so a local Android SDK or Godot Android export template is not required.

## Package

Use the project root containing:

```text
project.godot
export_presets.cfg
shipthis.json
scenes/
scripts/
autoload/
assets/
web/
```

The included `shipthis.json` uploads the complete source and local assets while excluding Godot import caches, local build outputs, screenshots, and temporary metadata. ShipThis’s Gradle Android pipeline will be used by default; the provided export preset supplies the project’s package and Android settings.

## Build an installable APK

Install Node.js 18 or newer, then install the ShipThis CLI:

```bash
npm install -g shipthis
shipthis login
```

From this project root, create or connect the ShipThis game. The wizard can create signing credentials, but it is not required for a local sideload build:

```bash
shipthis game wizard android
```

For an APK signed with ShipThis demo credentials and not published to Google Play, run:

```bash
shipthis game ship \
  --platform android \
  --useDemoCredentials \
  --skipPublish \
  --downloadAPK puttbound.apk \
  --follow
```

`--useDemoCredentials` implies `--skipPublish`; it creates an APK suitable for installing on a device without requiring a Google Play Console account. When the build completes, the file will be `puttbound.apk` in the current directory.

You can install it with:

```bash
adb install -r puttbound.apk
```

Or copy it to an Android device and open it there. Android may require enabling installation from that file source.

## Google Play bundle

For Google Play, build an AAB instead of an APK:

```bash
shipthis game ship \
  --platform android \
  --skipPublish \
  --download puttbound.aab \
  --follow
```

Use `shipthis game wizard android` and your own signing credentials before publishing. Do not use demo credentials for a production Play Store release.

## Troubleshooting

If the build fails, rerun with verbose output:

```bash
shipthis game ship \
  --platform android \
  --useDemoCredentials \
  --downloadAPK puttbound.apk \
  --follow \
  --verbose
```

The project uses Godot 4.7.2 and GDScript, not C#/.NET. It has no required backend, network permission, runtime download, account system, or external API. ShipThis will install the Android Gradle build template in its cloud build environment when needed.

## Relevant project settings

- Package identifier: `com.puttbound.worldsinmotion`
- Display name: `Puttbound: Worlds in Motion`
- Arm64 Android export enabled.
- Internet and network-state permissions disabled.
- Landscape-first gameplay presentation.
- Offline local saves and bundled WAV feedback cues.
