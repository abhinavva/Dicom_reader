# Dicom Reader

A Flutter desktop DICOM workstation that loads local studies, groups them by study and series, and displays image stacks using Cornerstone3D inside a WebView. Everything runs offline: the viewer is bundled with Vite (no CDN), and DICOM files are served from your machine via a local HTTP server.

---

## Implementation workflow (how it all fits together)

### Architecture (high level)

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Flutter app (Dart)                                                     │
│  • Picks folder/files → parses DICOM → groups studies/series            │
│  • Starts local HTTP server → registers bundle (tokens + image URLs)    │
│  • Shows UI: study/series list, toolbar, overlay HUD, metadata          │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                │  WebView loads viewer URL
                                │  (same host as server)
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Local HTTP server (Dart, 127.0.0.1:<port>)                             │
│  • GET /viewer/*     → serves bundled viewer from Flutter assets        │
│  • GET /dicom/<token> → streams DICOM file from disk (token = path)     │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                │  Browser loads index.html + viewer.bundle.js
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Cornerstone3D viewer (JavaScript, Vite bundle in WebView)              │
│  • Initializes once: Cornerstone, tools, DICOM loader, cache, viewport  │
│  • loadSeries(payload) → setStack(imageIds) → fetches /dicom/<token>    │
│  • Decodes DICOM, renders stack; reports viewport state back to Flutter │
└─────────────────────────────────────────────────────────────────────────┘
```

### End-to-end flow (what happens when you “Open Folder”)

1. **User** taps “Open Folder” and selects a directory.
2. **Flutter** opens the folder, recursively lists files, and parses each file’s DICOM header (Study/Series UIDs, patient, modality, etc.). Files are grouped into **studies** and **series**.
3. **Flutter** starts the **local HTTP server** (if not already running) and **registers** the bundle: for every DICOM instance it creates a token (base64url of file path) and a WADO-URI image ID: `wado-uri:http://127.0.0.1:<port>/dicom/<token>`.
4. **Flutter** receives a **viewer session**: viewer URL (`http://127.0.0.1:<port>/viewer/index.html`) and a map of series UID → payload (image IDs for that series).
5. **WebView** loads the viewer URL. The server serves `index.html` and `viewer.bundle.js` (and CSS, workers, WASM) from Flutter assets.
6. **Viewer script** runs: initializes Cornerstone, tools, DICOM loader, cache, and a single stack viewport. It exposes `window.cornerstoneViewer.loadSeries`, `setTool`, `resetViewport`, `startCine`, `stopCine`, etc.
7. **Flutter** calls `loadSeries(payload)` for the selected series by injecting JS. The viewer calls `viewport.setStack(imageIds, 0)`. For each image ID, Cornerstone requests `http://127.0.0.1:<port>/dicom/<token>`. The **server** streams the DICOM file from disk; the **viewer** decodes it and renders.
8. **Viewer** reports viewport state (zoom, window/level, slice index) and status to Flutter via the `viewerEvent` JS handler. Flutter updates the overlay HUD and status.

**In short:** DICOM stays on disk → server streams it by token → WebView runs the bundled viewer → viewer fetches by URL → Cornerstone decodes and renders. No CDN; no file paths exposed to the browser.

---

## When to build what

| You changed… | What to do |
|-------------|------------|
| **Only Flutter/Dart** (e.g. UI, server, providers) | Just run the app (see [Run](#run)). No viewer build. |
| **Viewer** (anything under `viewer/`: JS, CSS, HTML, Vite config) | Build the viewer, then run the app (see [Building the viewer](#building-the-viewer)). |

After changing viewer code, the app must serve the new bundle; that bundle lives in `assets/cornerstone_viewer/`, which is updated by the viewer build/copy step.

---

## Run

From the **app root** (`dicom_reader/`):

```bash
flutter pub get
flutter run
```

Then pick a device (e.g. Windows). To force a clean build (e.g. after changing assets or pubspec):

```bash
flutter clean
flutter run
```

---

## Building the viewer

The viewer is a Vite app in `viewer/`. Its output is copied into `assets/cornerstone_viewer/` so the Flutter app can serve it from the local server. **Do this after changing any file under `viewer/`** (e.g. `viewer/src/viewer.js`, `tools.js`, `main.js`, `styles.css`, `index.html`).

From the **app root**:

```bash
cd viewer
npm install          # only needed once (or when package.json changes)
npm run build:flutter
cd ..
flutter run
```

- `npm run build:flutter` runs `vite build` and then `node scripts/copy-to-flutter.js` (builds into `viewer/dist/` and copies to `assets/cornerstone_viewer/`).
- Alternatively: `npm run build` then `node scripts/copy-to-flutter.js` from inside `viewer/`.

The viewer bundle is fully offline-capable (no CDN). See `viewer/README.md` for more detail on the viewer project.

---

## Project structure

```text
dicom_reader/
├── lib/
│   ├── core/              # theme, utils, shared widgets
│   └── features/
│       └── dicom_viewer/
│           ├── application/   # controller, state, providers
│           ├── domain/        # entities, use cases, repo interface
│           ├── infrastructure/  # repo impl, DICOM parser, local viewer server
│           └── presentation/   # pages, viewer widget, workstation UI
├── assets/
│   └── cornerstone_viewer/   # Vite build output (index.html, assets/*.js, etc.)
├── viewer/                  # Vite + Cornerstone3D source (JS, CSS, HTML)
│   ├── src/
│   │   ├── main.js         # entry; exposes window.cornerstoneViewer
│   │   ├── viewer.js       # init, loadSeries, tools, cine, viewport state
│   │   ├── tools.js        # tool registration (zoom, pan, WL, scroll, length, angle)
│   │   └── styles.css
│   ├── index.html
│   ├── package.json
│   ├── vite.config.js
│   └── scripts/
│       └── copy-to-flutter.js
├── pubspec.yaml
└── README.md
```

---

## Features

- **Architecture:** Clean layers (presentation, application, domain, infrastructure); Riverpod for state; dark Material 3 workstation UI.
- **Loading:** Recursive folder scan or file pick; DICOM grouping by Study/Series UIDs; parsing of common tags (patient, study, series, modality, instance number).
- **Local server:** Dart `HttpServer` on loopback; serves viewer assets from Flutter bundle and DICOM by token under `/dicom/<token>`.
- **Viewer:** Vite-bundled Cornerstone3D (core, tools, dicom-image-loader); single stack viewport; cache and prefetch; cine playback; viewport state reported to Flutter.
- **Tools:** Zoom, pan, window/level, stack scroll (mouse wheel), length, angle, reset; tool state synced from Flutter.
- **Overlays:** Patient/study/series, zoom, window/level, slice index (from viewer events).
- **Metadata panel:** Driven by parsed DICOM tag summaries.

---

## Verification

- `flutter analyze`
- `flutter test`

---

## Windows note

Building the Windows app (and the WebView2 plugin) may require:

- **Developer Mode** (for symlinks) if `flutter build windows` complains about symlinks.
- **NuGet** for WebView2: install the [NuGet CLI](https://www.nuget.org/downloads) and ensure `nuget` is on your PATH.

---

## Summary flow (reference)

```text
User picks folder/files
    → Flutter parses DICOM, groups studies/series
    → Local server starts (if needed), registers bundle (tokens + WADO-URI URLs)
    → WebView loads viewer URL (same host)
    → Viewer (Vite bundle) initializes Cornerstone3D, viewport, tools
    → User selects series → Flutter injects loadSeries(payload)
    → Viewer fetches each image via wado-uri:http://127.0.0.1:port/dicom/<token>
    → Server streams DICOM from disk → Cornerstone decodes and renders
    → Viewport/tool events reported back to Flutter for HUD and status
```
