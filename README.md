# MapbuilderhexmapSR

Standalone Godot 4.7 project for a mobile-friendly hex map builder. This repository starts clean; editor interactions and map-generation behavior will be designed before feature code is added.

## Open in Godot

Open the repository root in Godot 4.7. The project starts in a blank 3D scene. It uses the Mobile renderer and Android ETC2/ASTC texture import setting.

## Layout

- `scenes/` — Godot scenes
- `scripts/` — editor and map logic
- `assets/models/` — 3D models
- `assets/materials/` — materials
- `assets/textures/` — textures
- `.github/workflows/android-apk.yml` — headless validation and Android APK build

## Build and validation

GitHub Actions downloads Godot 4.7.2 and its export templates when the workflow runs. It checks project import and main-scene startup before exporting the Android APK. The engine binaries are not stored in this repository.

The Android package ID is `com.tpylman90.mapbuilderhexmap`, matching the existing Mapbuilderhexmap signing backup so signed builds can update the installed app. Release credentials are supplied through GitHub Actions secrets, never committed here. Each build advances the Android version code and uploads a short-retention `MapbuilderhexmapSR-Android` artifact.

Add these repository secrets under **Settings → Secrets and variables → Actions**:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
