/**
 * main.js — Entry point.
 *
 * Binds the public API on `window.cornerstoneViewer` so Flutter's
 * InAppWebView can call methods via `evaluateJavascript`.
 */

import {
  initializeViewer,
  loadSeries,
  setTool,
  resetViewport,
  generateSeriesThumbnails,
  clearAnnotations,
  enableMpr,
  disableMpr,
  setMprOrientation,
  isMprActive,
  startCine,
  stopCine,
  setCineSpeed,
  isCinePlaying,
  isViewerReady,
} from './viewer.js';

import { bindStatusPill } from './bridge.js';

// Initialise the status pill before Cornerstone boots.
const pill = document.getElementById('status-pill');
if (pill) {
  pill.textContent = 'Viewer shell ready';
  bindStatusPill(pill);
}

window.cornerstoneViewer = {
  initializeViewer,
  loadSeries,
  setTool,
  resetViewport,
  generateSeriesThumbnails,
  clearAnnotations,
  enableMpr,
  disableMpr,
  setMprOrientation,
  isMprActive,
  startCine,
  stopCine,
  setCineSpeed,
  isCinePlaying,
  isViewerReady,
};
