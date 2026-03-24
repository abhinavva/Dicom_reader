import * as cornerstone from '@cornerstonejs/core';
import * as cornerstoneTools from '@cornerstonejs/tools';
import cornerstoneDICOMImageLoader from '@cornerstonejs/dicom-image-loader';
import * as dicomParser from 'dicom-parser';

import { registerStackTools, activatePrimaryTool } from './tools.js';

const RENDERING_ENGINE_ID = 'dicom-rendering-engine';
const VIEWPORT_ID = 'dicom-stack-viewport';
const CACHE_SIZE_BYTES = 2 * 1024 * 1024 * 1024;
const REPORT_DEBOUNCE_MS = 60;
const MAX_STACK_SIZE = 3000;

let viewerElement = null;
let statusPill = null;
let sliceOverlayElement = null;
let renderingEngine = null;
let viewport = null;
let toolGroup = null;
let toolNames = null;
let initialized = false;
let initializePromise = null;
let activeTool = 'windowLevel';
let currentSeries = null;
let reportTimer = null;

let cineTimer = null;
let cinePlaying = false;
let cineFps = 15;
let cineDirection = 1;

const stackContextPrefetch = cornerstoneTools.utilities?.stackContextPrefetch;

function emit(type, payload) {
  if (window.flutter_inappwebview?.callHandler) {
    window.flutter_inappwebview.callHandler('viewerEvent', { type, payload });
  }
}

function setStatus(message) {
  if (statusPill) {
    statusPill.textContent = message;
  }
  emit('status', message);
}

function normalizeImageId(imageId) {
  if (typeof imageId !== 'string') {
    return '';
  }

  // Compatibility with old builds that emitted wado-uri: instead of wadouri:
  if (imageId.startsWith('wado-uri:')) {
    return `wadouri:${imageId.substring('wado-uri:'.length)}`;
  }

  return imageId;
}

function normalizeImageIds(imageIds) {
  if (!Array.isArray(imageIds)) {
    throw new Error('imageIds must be an array');
  }

  const normalized = imageIds
    .map(normalizeImageId)
    .filter((id) => typeof id === 'string' && id.length > 0);

  if (normalized.length === 0) {
    throw new Error('No valid image IDs found in selected series');
  }

  if (normalized.length > MAX_STACK_SIZE) {
    return normalized.slice(0, MAX_STACK_SIZE);
  }

  return normalized;
}

function extractWindowLevel(properties) {
  const voiRange = properties?.voiRange;
  if (!voiRange) {
    return { windowWidth: null, windowCenter: null };
  }

  const upper = voiRange.upper ?? null;
  const lower = voiRange.lower ?? null;
  if (upper == null || lower == null) {
    return { windowWidth: null, windowCenter: null };
  }

  return {
    windowWidth: Math.abs(upper - lower),
    windowCenter: (upper + lower) / 2,
  };
}

function buildViewportState(statusMessage = null) {
  if (!viewport) {
    return null;
  }

  const properties = viewport.getProperties?.() ?? {};
  const { windowWidth, windowCenter } = extractWindowLevel(properties);
  const zoom = typeof viewport.getZoom === 'function' ? viewport.getZoom() : 1;
  const currentImageIndex =
    typeof viewport.getCurrentImageIdIndex === 'function'
      ? viewport.getCurrentImageIdIndex()
      : 0;
  const totalImages = currentSeries?.imageIds?.length ?? 0;

  return {
    zoom: Number.isFinite(zoom) ? zoom : 1,
    windowWidth,
    windowCenter,
    currentImageIndex,
    totalImages,
    isReady: true,
    statusMessage,
  };
}

function setSliceOverlay(currentImageIndex, totalImages) {
  if (!sliceOverlayElement) {
    return;
  }

  if (!Number.isFinite(totalImages) || totalImages <= 0) {
    sliceOverlayElement.textContent = '';
    sliceOverlayElement.style.display = 'none';
    return;
  }

  const safeCurrent = Math.max(0, Math.min(currentImageIndex, totalImages - 1));
  sliceOverlayElement.style.display = 'block';
  sliceOverlayElement.textContent = `Slice: ${safeCurrent + 1} / ${totalImages}`;
}

function reportViewportState(statusMessage = null) {
  const state = buildViewportState(statusMessage);
  if (!state) {
    return;
  }

  setSliceOverlay(state.currentImageIndex, state.totalImages);
  emit('viewport', state);
}

function scheduleViewportReport(statusMessage = null) {
  clearTimeout(reportTimer);
  reportTimer = setTimeout(() => {
    reportViewportState(statusMessage);
  }, REPORT_DEBOUNCE_MS);
}

function enablePrefetch() {
  if (!stackContextPrefetch || !viewerElement) {
    return;
  }

  try {
    stackContextPrefetch.enable(viewerElement, 0);
  } catch (_) {
    // Best effort.
  }
}

function disablePrefetch() {
  if (!stackContextPrefetch || !viewerElement) {
    return;
  }

  try {
    stackContextPrefetch.disable(viewerElement);
  } catch (_) {
    // Best effort.
  }
}

function registerListeners() {
  if (!viewerElement) {
    return;
  }

  const interactionEvents = ['wheel', 'mouseup', 'mouseleave', 'touchend', 'dblclick'];
  for (const eventName of interactionEvents) {
    viewerElement.addEventListener(eventName, () => scheduleViewportReport());
  }

  window.addEventListener('resize', () => {
    try {
      renderingEngine?.resize(true, false);
    } catch (_) {
      // Best effort.
    }
    scheduleViewportReport();
  });

  if (cornerstone.eventTarget?.addEventListener) {
    cornerstone.eventTarget.addEventListener(cornerstone.EVENTS.IMAGE_RENDERED, () => {
      scheduleViewportReport();
    });

    cornerstone.eventTarget.addEventListener(cornerstone.EVENTS.IMAGE_LOAD_FAILED, (event) => {
      const imageId = event?.detail?.imageId ?? 'unknown';
      const reason = event?.detail?.error?.message ?? event?.detail?.errorMessage ?? '';
      emit('imageLoadFailed', {
        imageId,
        reason,
      });
      scheduleViewportReport();
    });
  }

  viewerElement.addEventListener('webglcontextlost', (event) => {
    event.preventDefault();
    setStatus('WebGL context lost');
    emit('error', 'WebGL context lost. Please reload the study.');
  });
}

function configureDicomImageLoader() {
  if (cornerstoneDICOMImageLoader?.external) {
    cornerstoneDICOMImageLoader.external.cornerstone = cornerstone;
    cornerstoneDICOMImageLoader.external.dicomParser = dicomParser;
  }

  cornerstoneDICOMImageLoader.init({
    maxWebWorkers: Math.max(1, Math.min(6, navigator.hardwareConcurrency || 4)),
    useSharedArrayBuffer: false,
  });
}

function applyTool(toolId) {
  if (!toolGroup || !toolNames) {
    return;
  }

  if (toolId === 'crosshair') {
    if (viewerElement) {
      viewerElement.classList.add('crosshair-mode');
    }
    setStatus('Tool: crosshair');
    scheduleViewportReport('Tool: crosshair');
    return;
  }

  if (viewerElement) {
    viewerElement.classList.remove('crosshair-mode');
  }

  activatePrimaryTool(toolGroup, toolNames, toolId);
  setStatus(`Tool: ${toolId}`);
  scheduleViewportReport(`Tool: ${toolId}`);
}

function clearCineTimer() {
  if (cineTimer != null) {
    clearTimeout(cineTimer);
    cineTimer = null;
  }
}

function runCineLoop() {
  if (!cinePlaying || !viewport || !currentSeries?.imageIds?.length) {
    return;
  }

  const total = currentSeries.imageIds.length;
  const currentIndex = viewport.getCurrentImageIdIndex?.() ?? 0;

  let nextIndex = currentIndex + cineDirection;
  if (nextIndex >= total) {
    nextIndex = 0;
  }
  if (nextIndex < 0) {
    nextIndex = total - 1;
  }

  viewport.setImageIdIndex(nextIndex);
  viewport.render();
  scheduleViewportReport();

  cineTimer = setTimeout(runCineLoop, Math.round(1000 / cineFps));
}

async function findFirstRenderableImageIndex(imageIds) {
  for (let index = 0; index < imageIds.length; index += 1) {
    const imageId = imageIds[index];
    try {
      await cornerstone.imageLoader.loadAndCacheImage(imageId, {
        priority: 0,
        requestType: 'prefetch',
      });
      return index;
    } catch (_) {
      // Continue probing until we find a renderable image.
    }
  }

  return -1;
}

export async function initializeViewer() {
  if (initialized) {
    emit('ready', true);
    return;
  }

  if (initializePromise) {
    await initializePromise;
    return;
  }

  initializePromise = (async () => {
    viewerElement = document.getElementById('viewport');
    statusPill = document.getElementById('status-pill');
    sliceOverlayElement = document.getElementById('slice-overlay');

    if (!viewerElement) {
      throw new Error('Viewer viewport element was not found');
    }

    setStatus('Initializing Cornerstone...');

    await cornerstone.init();
    cornerstoneTools.init();

    try {
      cornerstone.cache.setMaxCacheSize(CACHE_SIZE_BYTES);
    } catch (_) {
      // Cache tuning is optional.
    }

    configureDicomImageLoader();

    renderingEngine = new cornerstone.RenderingEngine(RENDERING_ENGINE_ID);
    renderingEngine.enableElement({
      viewportId: VIEWPORT_ID,
      element: viewerElement,
      type: cornerstone.Enums.ViewportType.STACK,
      defaultOptions: {
        background: [0, 0, 0],
      },
    });

    viewport = renderingEngine.getViewport(VIEWPORT_ID);

    const toolRegistration = registerStackTools(RENDERING_ENGINE_ID, VIEWPORT_ID);
    toolGroup = toolRegistration.toolGroup;
    toolNames = toolRegistration.toolNames;

    registerListeners();

    initialized = true;
    setStatus('Cornerstone ready');
    reportViewportState('Viewer ready');
    emit('ready', true);
  })();

  try {
    await initializePromise;
  } catch (error) {
    const message = error?.message ?? String(error);
    setStatus('Cornerstone failed to initialize');
    emit('error', message);
    throw error;
  } finally {
    initializePromise = null;
  }
}

export async function loadSeries(payload) {
  try {
    await initializeViewer();

    if (!viewport) {
      throw new Error('Viewport was not initialized');
    }

    const imageIds = normalizeImageIds(payload?.imageIds ?? []);
    const firstRenderableIndex = await findFirstRenderableImageIndex(imageIds);
    if (firstRenderableIndex < 0) {
      throw new Error('No renderable DICOM images were found in this series.');
    }

    const orderedImageIds =
      firstRenderableIndex === 0
        ? imageIds
        : imageIds
            .slice(firstRenderableIndex)
            .concat(imageIds.slice(0, firstRenderableIndex));

    currentSeries = {
      studyInstanceUid: payload?.studyInstanceUid ?? '',
      seriesInstanceUid: payload?.seriesInstanceUid ?? '',
      imageIds: orderedImageIds,
    };

    stopCine();
    disablePrefetch();
    setStatus(`Loading ${orderedImageIds.length} slices...`);

    viewport.resetCamera();

    // Load a single image first for smooth first paint, then full stack.
    await viewport.setStack([orderedImageIds[0]], 0);
    viewport.render();
    await viewport.setStack(orderedImageIds, 0);
    viewport.render();

    // Reset viewport properties only after a valid csImage exists.
    if (typeof viewport.getCornerstoneImage === 'function' && viewport.getCornerstoneImage()) {
      viewport.resetProperties?.();
      viewport.render();
    }

    enablePrefetch();
    applyTool(activeTool);

    setStatus('Series loaded');
    reportViewportState('Series loaded');
  } catch (error) {
    const message = error?.message ?? String(error);
    setStatus('Failed to load series');
    emit('error', message);
  }
}

export async function setTool(toolId) {
  activeTool = toolId || 'windowLevel';
  applyTool(activeTool);
}

export async function resetViewport() {
  if (!viewport) {
    return;
  }

  try {
    viewport.resetCamera();
    if (typeof viewport.getCornerstoneImage === 'function' && viewport.getCornerstoneImage()) {
      viewport.resetProperties?.();
    }
    viewport.render();
    setStatus('Viewport reset');
    reportViewportState('Viewport reset');
  } catch (error) {
    const message = error?.message ?? String(error);
    setStatus('Reset failed');
    emit('error', message);
  }
}

async function _createSeriesThumbnail(imageId, seriesInstanceUid) {
  const normalizedImageId = normalizeImageId(imageId);
  if (!normalizedImageId) {
    return null;
  }

  const host = document.createElement('div');
  host.style.cssText = [
    'position: fixed',
    'left: -10000px',
    'top: -10000px',
    'width: 128px',
    'height: 128px',
    'opacity: 0',
    'pointer-events: none',
  ].join(';');
  document.body.appendChild(host);

  const thumbEngineId = `thumb-engine-${seriesInstanceUid}-${Date.now()}-${Math.floor(Math.random() * 10000)}`;
  const thumbViewportId = `thumb-viewport-${seriesInstanceUid}-${Date.now()}-${Math.floor(Math.random() * 10000)}`;

  let thumbEngine = null;

  try {
    thumbEngine = new cornerstone.RenderingEngine(thumbEngineId);
    thumbEngine.enableElement({
      viewportId: thumbViewportId,
      element: host,
      type: cornerstone.Enums.ViewportType.STACK,
      defaultOptions: {
        background: [0, 0, 0],
      },
    });

    const thumbViewport = thumbEngine.getViewport(thumbViewportId);
    await thumbViewport.setStack([normalizedImageId], 0);
    thumbViewport.render();

    await new Promise((resolve) => {
      requestAnimationFrame(() => requestAnimationFrame(resolve));
    });

    const canvas = host.querySelector('canvas');
    if (!canvas) {
      return null;
    }

    return canvas.toDataURL('image/jpeg', 0.72);
  } catch (error) {
    console.warn('Thumbnail generation failed for series:', seriesInstanceUid, error);
    return null;
  } finally {
    try {
      if (thumbEngine) {
        thumbEngine.disableElement(thumbViewportId);
        thumbEngine.destroy?.();
      }
    } catch (_) {
      // Best effort cleanup.
    }
    host.remove();
  }
}

export async function generateSeriesThumbnails(requests = []) {
  try {
    await initializeViewer();

    if (!Array.isArray(requests) || requests.length === 0) {
      return;
    }

    for (const request of requests) {
      const seriesInstanceUid = request?.seriesInstanceUid;
      const imageId = request?.imageId;

      if (!seriesInstanceUid || !imageId) {
        continue;
      }

      const dataUrl = await _createSeriesThumbnail(imageId, seriesInstanceUid);
      if (dataUrl) {
        emit('thumbnail', {
          seriesInstanceUid,
          dataUrl,
        });
      }
    }
  } catch (error) {
    const message = error?.message ?? String(error);
    emit('error', message);
  }
}
export function startCine(framesPerSecond = 15, direction = 1) {
  if (!viewport || !currentSeries?.imageIds?.length) {
    return;
  }

  cineFps = Math.max(1, Math.min(60, Number(framesPerSecond) || 15));
  cineDirection = direction >= 0 ? 1 : -1;
  cinePlaying = true;
  clearCineTimer();
  runCineLoop();
}

export function stopCine() {
  cinePlaying = false;
  clearCineTimer();
}

export function setCineSpeed(framesPerSecond = 15) {
  cineFps = Math.max(1, Math.min(60, Number(framesPerSecond) || 15));
}

export function isCinePlaying() {
  return cinePlaying;
}

export function isViewerReady() {
  return initialized;
}


