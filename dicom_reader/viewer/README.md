# Cornerstone3D Viewer Bundle

Vite-bundled Cornerstone3D viewer used by the Flutter DICOM workstation. **No CDN** — all dependencies are bundled for offline use.

## Build

```bash
npm install
npm run build
```

Output: `dist/index.html`, `dist/assets/viewer.bundle.js`, workers, WASM codecs, and CSS.

## Deploy into Flutter

After building, copy the bundle into Flutter assets so the app serves it from the local HTTP server:

```bash
npm run build:flutter
```

Or manually:

```bash
npm run build
node scripts/copy-to-flutter.js
```

This copies `dist/` → `../assets/cornerstone_viewer/`. The Flutter server serves `/viewer/*` from `assets/cornerstone_viewer/`.

## API (for Flutter WebView)

The viewer exposes a global API:

- `window.cornerstoneViewer.initializeViewer()` — init Cornerstone and create the stack viewport (idempotent).
- `window.cornerstoneViewer.loadSeries(payload)` — load a series. `payload`: `{ studyInstanceUid, seriesInstanceUid, imageIds }` where `imageIds` are WADO-URI URLs, e.g. `wado-uri:http://127.0.0.1:port/dicom/<token>`.
- `window.cornerstoneViewer.setTool(toolName)` — set active tool: `windowLevel`, `zoom`, `pan`, `stackScroll`, `crosshair`, `length`, `angle`.
- `window.cornerstoneViewer.resetViewport()` — reset camera and properties.

Events are sent to Flutter via `window.flutter_inappwebview.callHandler('viewerEvent', { type, payload })` (e.g. `ready`, `status`, `viewport`, `error`).

## Stack loading

Images are loaded lazily via Cornerstone’s image loader. Each `imageId` is fetched from the local server; the server streams the DICOM file from disk. Rendering is WebGL (GPU).
