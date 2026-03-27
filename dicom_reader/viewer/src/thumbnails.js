/**
 * thumbnails.js — Offscreen series thumbnail generation.
 *
 * Uses a SINGLE shared offscreen RenderingEngine to avoid leaking
 * WebGL contexts.  Thumbnails are rendered one at a time on a hidden
 * 128×128 canvas and emitted as JPEG data-URLs.
 */

import * as cornerstone from '@cornerstonejs/core';

import { emit } from './bridge.js';
import { normalizeImageId } from './imageIds.js';

/* ------------------------------------------------------------------ */
/*  Shared offscreen rendering engine (one WebGL context for all)      */
/* ------------------------------------------------------------------ */

const THUMB_ENGINE_ID = 'thumb-engine-shared';
const THUMB_VIEWPORT_ID = 'thumb-viewport-shared';

/** @type {cornerstone.RenderingEngine|null} */
let sharedEngine = null;
/** @type {HTMLDivElement|null} */
let sharedHost = null;

/**
 * Lazily create the shared offscreen engine + hidden host element.
 * Returns the shared StackViewport.
 */
function getOrCreateThumbViewport() {
  if (sharedEngine && sharedHost && sharedHost.isConnected) {
    const vp = sharedEngine.getViewport(THUMB_VIEWPORT_ID);
    if (vp) return vp;
    // viewport disappeared — rebuild
    destroySharedEngine();
  }

  sharedHost = document.createElement('div');
  sharedHost.style.cssText = [
    'position: fixed',
    'left: -10000px',
    'top: -10000px',
    'width: 128px',
    'height: 128px',
    'opacity: 0',
    'pointer-events: none',
  ].join(';');
  document.body.appendChild(sharedHost);

  sharedEngine = new cornerstone.RenderingEngine(THUMB_ENGINE_ID);
  sharedEngine.enableElement({
    viewportId: THUMB_VIEWPORT_ID,
    element: sharedHost,
    type: cornerstone.Enums.ViewportType.STACK,
    defaultOptions: { background: [0, 0, 0] },
  });

  return sharedEngine.getViewport(THUMB_VIEWPORT_ID);
}

/**
 * Tear down the shared engine (call when no longer needed).
 */
function destroySharedEngine() {
  try {
    if (sharedEngine) {
      sharedEngine.disableElement(THUMB_VIEWPORT_ID);
      sharedEngine.destroy?.();
    }
  } catch (_) {
    // best effort
  }
  sharedEngine = null;
  sharedHost?.remove();
  sharedHost = null;
}

/**
 * Render a single thumbnail for one series using the shared viewport.
 *
 * @param {string} imageId             - Image ID for the first frame.
 * @param {string} seriesInstanceUid   - Series UID (for logging only).
 * @returns {Promise<string|null>}     - JPEG data-URL or null on failure.
 */
async function createSeriesThumbnail(imageId, seriesInstanceUid) {
  const normalizedImageId = normalizeImageId(imageId);
  if (!normalizedImageId) {
    return null;
  }

  try {
    const thumbViewport = getOrCreateThumbViewport();
    if (!thumbViewport) return null;

    // Pre-load the image into cache before setting the stack.
    // This avoids the renderViewport race where the viewport's
    // internal actor isn't ready when render() is called.
    try {
      await cornerstone.imageLoader.loadAndCacheImage(normalizedImageId, {
        priority: -5,
        requestType: 'prefetch',
      });
    } catch (_) {
      // Image failed to load — can't generate thumbnail.
      return null;
    }

    await thumbViewport.setStack([normalizedImageId], 0);

    // Wait for three animation frames so the viewport fully
    // processes the stack and creates its internal rendering actor.
    await new Promise((resolve) => {
      requestAnimationFrame(() =>
        requestAnimationFrame(() =>
          requestAnimationFrame(resolve),
        ),
      );
    });

    // Guard: only call render if the engine still has this viewport.
    if (!sharedEngine?.getViewport?.(THUMB_VIEWPORT_ID)) {
      return null;
    }

    try {
      thumbViewport.render();
    } catch (_) {
      // renderViewport can fail on some images — skip silently.
      return null;
    }

    // One more frame for the rendered pixels to land on the canvas.
    await new Promise((resolve) => {
      requestAnimationFrame(resolve);
    });

    const canvas = sharedHost?.querySelector('canvas');
    if (!canvas) {
      return null;
    }

    return canvas.toDataURL('image/jpeg', 0.72);
  } catch (error) {
    console.warn('Thumbnail generation failed for series:', seriesInstanceUid, error);
    return null;
  }
}

/**
 * Generate thumbnails for a batch of series.
 *
 * @param {Array<{ seriesInstanceUid: string, imageId: string }>} requests
 */
export async function generateSeriesThumbnails(requests = []) {
  if (!Array.isArray(requests) || requests.length === 0) {
    return;
  }

  for (const request of requests) {
    const seriesInstanceUid = request?.seriesInstanceUid;
    const imageId = request?.imageId;

    if (!seriesInstanceUid || !imageId) {
      continue;
    }

    const dataUrl = await createSeriesThumbnail(imageId, seriesInstanceUid);
    if (dataUrl) {
      emit('thumbnail', { seriesInstanceUid, dataUrl });
    }
  }

  // Tear down the shared engine to free the extra WebGL context.
  destroySharedEngine();
}
