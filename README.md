# DicomReader

Desktop DICOM workstation built with Flutter and a bundled Cornerstone3D WebView viewer.

This repository root contains the Flutter application in `dicom_reader/`.

## Repository Layout

- `dicom_reader/` - main Flutter desktop app and bundled viewer assets
- `dicom_reader/viewer/` - Vite + Cornerstone3D source used by the WebView

## Quick Start

From this repository root:

```bash
cd dicom_reader
flutter pub get
flutter run
```

## When You Change Viewer Code

If you modify anything in `dicom_reader/viewer/`, rebuild and copy the viewer bundle into Flutter assets:

```bash
cd dicom_reader/viewer
npm install
npm run build:flutter
cd ..
flutter run
```

`build:flutter` runs Vite build and copies output into `dicom_reader/assets/cornerstone_viewer/`.

## Tech Stack

- Flutter (desktop app, local loopback server, workstation UI)
- Riverpod (state management)
- InAppWebView (viewer host)
- Cornerstone3D + Vite (DICOM rendering bundle)

## Verification

From `dicom_reader/`:

```bash
flutter analyze
flutter test
```

## Documentation

- App architecture and full workflow: `dicom_reader/README.md`
- Viewer bundle details and JS API: `dicom_reader/viewer/README.md`
