# MapbuilderhexmapSR

Standalone Godot 4.7 project for a mobile-friendly hex map builder. It opens on a 64 × 128 editable hex field with elevation, ground-painting, brush-size, camera, and stroke undo/redo tools.

## Open in Godot

Open the repository root in Godot 4.7. Tap or drag across the board to edit. Raise and Lower change elevation by one step, with limits of +15 and −15. Choose a ground type to paint, then use the brush-size picker to change the affected area. Undo and Redo apply to whole strokes. Turn on Pan view to drag the camera; the − and + buttons zoom. The initial flat grid uses a plain color for clear cell visibility before art assets are added.

The hexes use pointy-top geometry aligned to the offset-row grid. Each cell stores elevation and ground type independently. Elevated edges generate faceted rock faces between cells. Objects, textures, save/load, and export of authored maps are not part of this first editing pass.

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
