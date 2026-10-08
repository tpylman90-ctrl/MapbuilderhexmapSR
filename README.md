# MapbuilderhexmapSR

A standalone Godot 4.7 mobile-friendly hex map builder. The editor opens on a 64 × 128 board with 8,192 editable hexes and a close camera mode for detailed terrain work.

## Editor workspaces

The side panel is divided into three workspaces:

- **Terrain** — raise, lower, flatten, smooth, build hills and ridges, choose a 1–8 hex brush, paint Grass, Dirt, Stone, Water, Sand, Snow, Mud, or Road, sample a tile, and fill the ground layer.
- **Objects** — stamp the supplied Cartoon House model or low-poly Oak Tree, Pine, and Boulder props. Rotate and scale the next stamp, or use Erase Object to remove a placed item. Object placement and removal support Undo and Redo.
- **Map** — save and load portable .hexmap files, generate an island or highlands layout, start a blank map, toggle hex outlines and grass detail, tune ground and cliff texture detail, and select low, balanced, or high animated water mesh detail.

Map files store the board dimensions, elevation, terrain ids, and placed objects. They are saved through Godot's user:// file picker so builds can read and write them on Android. Map generation replaces terrain and elevation as one undoable operation. A blank-map reset clears the current undo history.

## Terrain rendering

Terrain material shaders layer world-space procedural noise for grass mottling, soil grain, and sand ripples. Water uses a dedicated radially subdivided mesh with animated crossing waves, a soft shoreline fade, and a narrow foam highlight. Exposed edges form continuous stylized rock walls with displaced low-poly facets, warm mineral variation, strata, cracks, moss, and a terrain-colored grass lip. The Map workspace has live detail sliders for the ground and cliff shaders plus three water-mesh detail levels. Grass tufts use one instanced mesh across the board to keep draw calls low.

## Camera and input

The camera HUD provides zoom, slide-to-pan, tilt, orbit, and Home reset. The zoom control reaches close enough to inspect a handful of tiles. Pinch and mouse-wheel gestures zoom, and dragging pans while Slide is enabled. Touch or click the board to sculpt, paint, or place objects.

## Project layout

- scenes/ — main scene
- scripts/ — editor, hex-grid data, and board rendering
- assets/models/ — placeable 3D models
- assets/materials/ — procedural terrain shaders
- .github/workflows/android-apk.yml — headless validation and signed Android APK build

## Open and build

Open the repository root in Godot 4.7. GitHub Actions downloads Godot 4.7.2 and its export templates, checks project import and main-scene startup, then exports the Android APK. Release signing keys come from GitHub Actions secrets and are never committed. Each signed build uses the existing Android package id so it can update the installed app.

Required repository secrets:

- ANDROID_KEYSTORE_BASE64
- ANDROID_KEYSTORE_PASSWORD
- ANDROID_KEY_ALIAS
- ANDROID_KEY_PASSWORD
