import {
  initializeViewer,
  loadSeries,
  setTool,
  resetViewport,
  generateSeriesThumbnails,
  startCine,
  stopCine,
  setCineSpeed,
  isCinePlaying,
  isViewerReady,
} from './viewer.js';

const statusPill = document.getElementById('status-pill');
if (statusPill) {
  statusPill.textContent = 'Viewer shell ready';
}

window.cornerstoneViewer = {
  initializeViewer,
  loadSeries,
  setTool,
  resetViewport,
  generateSeriesThumbnails,
  startCine,
  stopCine,
  setCineSpeed,
  isCinePlaying,
  isViewerReady,
};
