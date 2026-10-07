# MapbuilderhexmapSR

Standalone Godot 4.7 project for a mobile-friendly hex map builder. It opens on a 64 × 128 editable hex field with elevation, ground-painting, brush-size, camera, and stroke undo/redo tools.

## Open in Godot

Open the repository root in Godot 4.7. The Sculpt panel provides Raise, Lower, Flatten, Smooth, Hill, and Ridge tools; brush sizes range from 1 to 8 hexes, and elevation is limited to +15 and −15. The Ground panel paints Grass, Dirt, Stone, Water, Sand, Snow, Mud, and Road. Sample picks an existing ground type, while Fill board paints the whole ground layer after confirmation. Undo and Redo apply to whole strokes or a layer fill. The floating camera HUD provides zoom, slide, tilt, orbit, and reset controls; mouse-wheel and pinch gestures zoom, while the Slide button enables drag-to-pan. Hex caps render complete top faces, with a separate subdued outline grid over the flat color terrain.

The hexes use pointy-top geometry aligned to the offset-row grid. Thin gaps define the cell edges without overlapping side faces. Each cell stores elevation and ground type independently; elevated edges generate faceted rock faces between cells. Objects, textures, save/load, and export of authored maps are not part of this terrain editing pass.

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
