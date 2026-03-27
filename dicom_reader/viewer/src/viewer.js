/**
 * viewer.js — Core viewer orchestrator.
 *
 * Wires together Cornerstone3D initialization, series loading, tool
 * management, and event listeners.  Domain logic lives in dedicated
 * modules:
 *
 *   bridge.js       — Flutter ↔ JS communication
 *   imageIds.js     — Image ID normalization / validation
 *   viewportState.js— Viewport state extraction & reporting
 *   loadProgress.js — Series image load progress tracking
 *   cine.js         — Cine loop playback
 *   thumbnails.js   — Offscreen thumbnail generation
 *   tools.js        — Cornerstone tool registration
 */

import * as cornerstone from '@cornerstonejs/core';
import * as cornerstoneTools from '@cornerstonejs/tools';
import cornerstoneDICOMImageLoader from '@cornerstonejs/dicom-image-loader';
import * as dicomParser from 'dicom-parser';

import { emit, bindStatusPill, setStatus } from './bridge.js';
import { normalizeImageIds } from './imageIds.js';
import {
  reportViewportState,
  scheduleViewportReport,
} from './viewportState.js';
import { resetProgress, recordImage } from './loadProgress.js';
import {
  startCine as startCineLoop,
  stopCine as stopCineLoop,
  setCineSpeed as setCineLoopSpeed,
  isCinePlaying,
} from './cine.js';
import { generateSeriesThumbnails } from './thumbnails.js';
import { registerStackTools, activatePrimaryTool, clearAnnotations } from './tools.js';

/* ------------------------------------------------------------------ */
/*  Constants                                                          */
/* ------------------------------------------------------------------ */

const RENDERING_ENGINE_ID = 'dicom-rendering-engine';
const VIEWPORT_ID = 'dicom-stack-viewport';
const CACHE_SIZE_BYTES = 2 * 1024 * 1024 * 1024;

/* ------------------------------------------------------------------ */
/*  Module-level state                                                 */
/* ------------------------------------------------------------------ */

let viewerElement = null;
let viewportContainer = null;
let sliceOverlayElement = null;
let renderingEngine = null;
let viewport = null;
let toolGroup = null;
let toolNames = null;
let initialized = false;
let initializePromise = null;
let activeTool = 'windowLevel';
let currentSeries = null;
let mprActive = false;
let currentVolumeId = null;

/** MPR viewport elements and IDs (used only in MPR mode). */
let mprViewportElements = [];
const MPR_VIEWPORT_IDS = ['mpr-axial', 'mpr-sagittal', 'mpr-coronal'];

const VOLUME_ID_PREFIX = 'cornerstoneStreamingImageVolume:';

const stackContextPrefetch = cornerstoneTools.utilities?.stackContextPrefetch;

/* ------------------------------------------------------------------ */
/*  Prefetch helpers                                                   */
/* ------------------------------------------------------------------ */

function enablePrefetch() {
  if (!stackContextPrefetch || !viewerElement) return;
  try { stackContextPrefetch.enable(viewerElement, 0); } catch (_) { /* best effort */ }
}

function disablePrefetch() {
  if (!stackContextPrefetch || !viewerElement) return;
  try { stackContextPrefetch.disable(viewerElement); } catch (_) { /* best effort */ }
}

/* ------------------------------------------------------------------ */
/*  DICOM image loader configuration                                   */
/* ------------------------------------------------------------------ */

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

/* ------------------------------------------------------------------ */
/*  Tool application                                                   */
/* ------------------------------------------------------------------ */

function applyTool(toolId) {
  if (!toolGroup || !toolNames) return;

  if (toolId === 'crosshair') {
    viewerElement?.classList.add('crosshair-mode');
    setStatus('Tool: crosshair');
    scheduleViewportReport(viewport, currentSeries, sliceOverlayElement, 'Tool: crosshair');
    return;
  }

  viewerElement?.classList.remove('crosshair-mode');
  activatePrimaryTool(toolGroup, toolNames, toolId);
  setStatus(`Tool: ${toolId}`);
  scheduleViewportReport(viewport, currentSeries, sliceOverlayElement, `Tool: ${toolId}`);
}

/* ------------------------------------------------------------------ */
/*  Event listeners                                                    */
/* ------------------------------------------------------------------ */

function registerListeners() {
  if (!viewerElement) return;

  const interactionEvents = ['wheel', 'mouseup', 'mouseleave', 'touchend', 'dblclick'];
  for (const eventName of interactionEvents) {
    viewerElement.addEventListener(eventName, () =>
      scheduleViewportReport(viewport, currentSeries, sliceOverlayElement),
    );
  }

  window.addEventListener('resize', () => {
    try { renderingEngine?.resize(true, false); } catch (_) { /* best effort */ }
    scheduleViewportReport(viewport, currentSeries, sliceOverlayElement);
  });

  if (cornerstone.eventTarget?.addEventListener) {
    cornerstone.eventTarget.addEventListener(cornerstone.EVENTS.IMAGE_RENDERED, () => {
      scheduleViewportReport(viewport, currentSeries, sliceOverlayElement);
    });

    cornerstone.eventTarget.addEventListener(cornerstone.EVENTS.IMAGE_LOAD_FAILED, (event) => {
      const imageId = event?.detail?.imageId ?? 'unknown';
      const reason = event?.detail?.error?.message ?? event?.detail?.errorMessage ?? '';
      emit('imageLoadFailed', { imageId, reason });

      // Count failed images as "loaded" for progress purposes.
      recordImage(imageId, currentSeries?.imageIds ?? []);
      scheduleViewportReport(viewport, currentSeries, sliceOverlayElement);
    });

    cornerstone.eventTarget.addEventListener(cornerstone.EVENTS.IMAGE_CACHE_IMAGE_ADDED, (event) => {
      const imageId = event?.detail?.imageId ?? '';
      recordImage(imageId, currentSeries?.imageIds ?? []);
    });
  }

  viewerElement.addEventListener('webglcontextlost', (event) => {
    event.preventDefault();
    setStatus('WebGL context lost — recovering…');
    emit('error', 'WebGL context lost. Attempting recovery…');

    // Attempt to re-create the rendering engine on the same element.
    setTimeout(async () => {
      try {
        renderingEngine?.destroy?.();
      } catch (_) { /* best effort */ }

      try {
        renderingEngine = new cornerstone.RenderingEngine(RENDERING_ENGINE_ID);
        renderingEngine.enableElement({
          viewportId: VIEWPORT_ID,
          element: viewerElement,
          type: cornerstone.Enums.ViewportType.STACK,
          defaultOptions: { background: [0, 0, 0] },
        });
        viewport = renderingEngine.getViewport(VIEWPORT_ID);

        // Re-apply tools to the fresh viewport.
        const toolReg = registerStackTools(RENDERING_ENGINE_ID, VIEWPORT_ID);
        toolGroup = toolReg.toolGroup;
        toolNames = toolReg.toolNames;

        // Re-load the current series if we had one.
        if (currentSeries?.imageIds?.length) {
          await viewport.setStack(currentSeries.imageIds, 0);
          viewport.render();
          applyTool(activeTool);
          enablePrefetch();
        }

        setStatus('WebGL context recovered');
        reportViewportState(viewport, currentSeries, sliceOverlayElement, 'Context recovered');
      } catch (err) {
        setStatus('Recovery failed');
        emit('error', `WebGL recovery failed: ${err?.message ?? err}`);
      }
    }, 500);
  });
}

/* ------------------------------------------------------------------ */
/*  Image probing                                                      */
/* ------------------------------------------------------------------ */

async function findFirstRenderableImageIndex(imageIds) {
  for (let index = 0; index < imageIds.length; index += 1) {
    try {
      await cornerstone.imageLoader.loadAndCacheImage(imageIds[index], {
        priority: 0,
        requestType: 'prefetch',
      });
      return index;
    } catch (_) {
      // Continue probing.
    }
  }
  return -1;
}

/* ------------------------------------------------------------------ */
/*  Public API                                                         */
/* ------------------------------------------------------------------ */

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
    viewportContainer = document.getElementById('viewport-container');
    viewerElement = document.getElementById('viewport');
    sliceOverlayElement = document.getElementById('slice-overlay');
    bindStatusPill(document.getElementById('status-pill'));

    if (!viewerElement) {
      throw new Error('Viewer viewport element was not found');
    }

    setStatus('Initializing Cornerstone...');

    await cornerstone.init({
      gpuTier: { value: 'medium' },
      rendering: {
        preferSizeOverAccuracy: true,
        useNorm16Texture: true,
      },
    });
    cornerstoneTools.init();

    try { cornerstone.cache.setMaxCacheSize(CACHE_SIZE_BYTES); } catch (_) { /* optional */ }

    configureDicomImageLoader();

    renderingEngine = new cornerstone.RenderingEngine(RENDERING_ENGINE_ID);
    renderingEngine.enableElement({
      viewportId: VIEWPORT_ID,
      element: viewerElement,
      type: cornerstone.Enums.ViewportType.STACK,
      defaultOptions: { background: [0, 0, 0] },
    });

    viewport = renderingEngine.getViewport(VIEWPORT_ID);

    const toolRegistration = registerStackTools(RENDERING_ENGINE_ID, VIEWPORT_ID);
    toolGroup = toolRegistration.toolGroup;
    toolNames = toolRegistration.toolNames;

    registerListeners();

    initialized = true;
    setStatus('Cornerstone ready');
    reportViewportState(viewport, currentSeries, sliceOverlayElement, 'Viewer ready');
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

    // Exit MPR mode when switching series
    if (mprActive) {
      mprActive = false;

      // Disable the 3 MPR viewports.
      for (const vpId of MPR_VIEWPORT_IDS) {
        try { renderingEngine.disableElement(vpId); } catch (_) { }
      }
      destroyMprViewportElements();
      viewportContainer.classList.remove('mpr-active');
      viewerElement.style.display = '';

      renderingEngine.enableElement({
        viewportId: VIEWPORT_ID,
        element: viewerElement,
        type: cornerstone.Enums.ViewportType.STACK,
        defaultOptions: { background: [0, 0, 0] },
      });
      viewport = renderingEngine.getViewport(VIEWPORT_ID);
      const toolReg = registerStackTools(RENDERING_ENGINE_ID, VIEWPORT_ID);
      toolGroup = toolReg.toolGroup;
      toolNames = toolReg.toolNames;
      emit('mprMode', { enabled: false });
    }

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

    // --- Clean up previous series to free GPU textures & memory ----
    const previousImageIds = currentSeries?.imageIds;
    stopCine();
    disablePrefetch();

    // Clear the viewport stack before purging cache so Cornerstone
    // releases its texture references first.
    try {
      await viewport.setStack([orderedImageIds[0]], 0);
    } catch (_) { /* best effort */ }

    // Purge cached images from the OLD series to free GPU memory and
    // avoid stale WebGL textures.
    if (previousImageIds?.length) {
      for (const id of previousImageIds) {
        try { cornerstone.cache.removeImageLoadObject(id); } catch (_) { /* ok */ }
      }
    }
    // ---------------------------------------------------------------

    currentSeries = {
      studyInstanceUid: payload?.studyInstanceUid ?? '',
      seriesInstanceUid: payload?.seriesInstanceUid ?? '',
      imageIds: orderedImageIds,
    };

    // Reset progress tracking for this series.
    resetProgress(currentSeries.seriesInstanceUid, orderedImageIds.length);

    setStatus(`Loading ${orderedImageIds.length} slices...`);

    viewport.resetCamera();

    // Set the full stack and render.
    await viewport.setStack(orderedImageIds, 0);
    viewport.render();

    // Reset viewport properties only after a valid csImage exists.
    try {
      const csImage = typeof viewport.getCornerstoneImage === 'function'
        ? viewport.getCornerstoneImage()
        : null;
      if (csImage) {
        viewport.resetProperties?.();
        viewport.render();
      }
    } catch (_) {
      // Some images do not expose properties safely — continue.
    }

    enablePrefetch();
    applyTool(activeTool);

    setStatus('Series loaded');
    reportViewportState(viewport, currentSeries, sliceOverlayElement, 'Series loaded');
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
  if (!viewport) return;

  try {
    viewport.resetCamera();
    try {
      const csImage = typeof viewport.getCornerstoneImage === 'function'
        ? viewport.getCornerstoneImage()
        : null;
      if (csImage) {
        viewport.resetProperties?.();
      }
    } catch (_) { /* best effort */ }
    viewport.render();
    setStatus('Viewport reset');
    reportViewportState(viewport, currentSeries, sliceOverlayElement, 'Viewport reset');
  } catch (error) {
    const message = error?.message ?? String(error);
    setStatus('Reset failed');
    emit('error', message);
  }
}

export { generateSeriesThumbnails } from './thumbnails.js';
export { isCinePlaying } from './cine.js';
export { clearAnnotations } from './tools.js';

export function startCine(framesPerSecond = 15, direction = 1) {
  if (!viewport || !currentSeries?.imageIds?.length) return;

  const fps = Math.max(1, Math.min(60, Number(framesPerSecond) || 15));
  const dir = direction >= 0 ? 1 : -1;
  startCineLoop(viewport, currentSeries, sliceOverlayElement, fps);
}

export function stopCine() {
  stopCineLoop();
}

export function setCineSpeed(framesPerSecond = 15) {
  const fps = Math.max(1, Math.min(60, Number(framesPerSecond) || 15));
  setCineLoopSpeed(fps, viewport, currentSeries, sliceOverlayElement);
}

/* ------------------------------------------------------------------ */
/*  MPR (Multi-Planar Reconstruction)                                  */
/* ------------------------------------------------------------------ */

function resolveOrientation(orientation) {
  const map = {
    axial: cornerstone.Enums.OrientationAxis.AXIAL,
    sagittal: cornerstone.Enums.OrientationAxis.SAGITTAL,
    coronal: cornerstone.Enums.OrientationAxis.CORONAL,
  };
  return map[orientation] ?? map.axial;
}

const MPR_ORIENTATIONS = ['axial', 'sagittal', 'coronal'];

/**
 * Create the 3 MPR viewport elements inside the container.
 * Returns the array of DOM elements.
 */
function createMprViewportElements() {
  // Remove existing MPR elements if any.
  destroyMprViewportElements();

  const elements = [];
  for (let i = 0; i < 3; i++) {
    const el = document.createElement('div');
    el.id = MPR_VIEWPORT_IDS[i];
    el.className = 'viewport';
    el.style.position = 'relative';

    // Add orientation label.
    const label = document.createElement('div');
    label.className = 'mpr-label';
    label.textContent = MPR_ORIENTATIONS[i].toUpperCase();
    el.appendChild(label);

    viewportContainer.appendChild(el);
    elements.push(el);
  }
  return elements;
}

function destroyMprViewportElements() {
  for (const id of MPR_VIEWPORT_IDS) {
    const el = document.getElementById(id);
    if (el) el.remove();
  }
  mprViewportElements = [];
}

export async function enableMpr(orientation = 'axial') {
  try {
    await initializeViewer();
    if (!currentSeries?.imageIds?.length || !renderingEngine) {
      emit('error', 'No series loaded for MPR');
      return;
    }

    stopCine();
    disablePrefetch();

    const newVolumeId = `${VOLUME_ID_PREFIX}${currentSeries.seriesInstanceUid}`;

    // Remove old volume if switching series.
    if (currentVolumeId && currentVolumeId !== newVolumeId) {
      try { cornerstone.cache.removeVolumeLoadObject(currentVolumeId); } catch (_) { }
    }
    currentVolumeId = newVolumeId;

    setStatus('Loading MPR…');

    // Hide the stack viewport element.
    viewerElement.style.display = 'none';

    // Disable the stack viewport to free its WebGL resources.
    try { renderingEngine.disableElement(VIEWPORT_ID); } catch (_) { }

    // Create 3 MPR viewport elements.
    viewportContainer.classList.add('mpr-active');
    mprViewportElements = createMprViewportElements();

    // Enable 3 ORTHOGRAPHIC viewports in the same rendering engine.
    for (let i = 0; i < 3; i++) {
      renderingEngine.enableElement({
        viewportId: MPR_VIEWPORT_IDS[i],
        element: mprViewportElements[i],
        type: cornerstone.Enums.ViewportType.ORTHOGRAPHIC,
        defaultOptions: {
          orientation: resolveOrientation(MPR_ORIENTATIONS[i]),
          background: [0, 0, 0],
        },
      });
    }

    // Create (or reuse) the volume.
    let volume = cornerstone.cache.getVolume(currentVolumeId);
    if (!volume) {
      volume = await cornerstone.volumeLoader.createAndCacheVolume(currentVolumeId, {
        imageIds: currentSeries.imageIds,
      });
      volume.load();
    }

    // Set the shared volume on all 3 viewports.
    await cornerstone.setVolumesForViewports(
      renderingEngine,
      [{ volumeId: currentVolumeId }],
      MPR_VIEWPORT_IDS,
    );

    // Re-register tools for all MPR viewports.
    const toolReg = registerStackTools(RENDERING_ENGINE_ID, MPR_VIEWPORT_IDS);
    toolGroup = toolReg.toolGroup;
    toolNames = toolReg.toolNames;
    applyTool(activeTool);

    // Use the primary viewport (axial) for state reporting.
    viewport = renderingEngine.getViewport(MPR_VIEWPORT_IDS[0]);

    mprActive = true;
    setStatus('MPR: axial | sagittal | coronal');
    emit('mprMode', { enabled: true, orientation: 'axial' });
    scheduleViewportReport(viewport, currentSeries, sliceOverlayElement, 'MPR active');
  } catch (error) {
    setStatus('MPR failed');
    emit('error', `MPR error: ${error?.message ?? error}`);
  }
}

export async function disableMpr() {
  try {
    if (!renderingEngine || !mprActive) return;

    mprActive = false;
    stopCine();

    // Disable the 3 MPR viewports.
    for (const vpId of MPR_VIEWPORT_IDS) {
      try { renderingEngine.disableElement(vpId); } catch (_) { }
    }

    // Remove MPR DOM elements.
    destroyMprViewportElements();
    viewportContainer.classList.remove('mpr-active');

    // Show the stack viewport element again.
    viewerElement.style.display = '';

    // Re-enable the stack viewport.
    renderingEngine.enableElement({
      viewportId: VIEWPORT_ID,
      element: viewerElement,
      type: cornerstone.Enums.ViewportType.STACK,
      defaultOptions: { background: [0, 0, 0] },
    });

    viewport = renderingEngine.getViewport(VIEWPORT_ID);

    // Re-register tools.
    const toolReg = registerStackTools(RENDERING_ENGINE_ID, VIEWPORT_ID);
    toolGroup = toolReg.toolGroup;
    toolNames = toolReg.toolNames;

    // Re-load the series as a stack.
    if (currentSeries?.imageIds?.length) {
      await viewport.setStack(currentSeries.imageIds, 0);
      viewport.render();
      enablePrefetch();
    }

    applyTool(activeTool);
    setStatus('Stack mode');
    emit('mprMode', { enabled: false });
    scheduleViewportReport(viewport, currentSeries, sliceOverlayElement, 'Stack mode');
  } catch (error) {
    setStatus('Failed to exit MPR');
    emit('error', `Exit MPR error: ${error?.message ?? error}`);
  }
}

export async function setMprOrientation(orientation = 'axial') {
  if (!mprActive) {
    return enableMpr(orientation);
  }
  // In the new MPR design, all 3 orientations are always visible.
  // This is a no-op but we emit the event for Flutter state sync.
  emit('mprMode', { enabled: true, orientation });
}

export function isMprActive() {
  return mprActive;
}

export function isViewerReady() {
  return initialized;
}

