/**
 * cine.js — Cine loop playback for stack viewports.
 *
 * Controls frame-by-frame navigation at a configurable FPS,
 * with optional bounce (ping-pong) direction.
 */

import { scheduleViewportReport } from './viewportState.js';

/** @type {number|null} */
let cineTimer = null;
/** @type {boolean} */
let playing = false;
/** @type {number} */
let fps = 15;
/** @type {1|-1} */
let direction = 1;

/**
 * Stop the interval timer if running.
 */
function clearCineTimer() {
  if (cineTimer !== null) {
    clearInterval(cineTimer);
    cineTimer = null;
  }
}

/**
 * Advance the viewport by one frame.
 *
 * @param {object}           viewport
 * @param {object|null}      currentSeries
 * @param {HTMLElement|null} sliceOverlayElement
 */
function runCineLoop(viewport, currentSeries, sliceOverlayElement) {
  if (!viewport || !currentSeries?.imageIds?.length) {
    return;
  }

  const totalImages = currentSeries.imageIds.length;
  const current =
    typeof viewport.getCurrentImageIdIndex === 'function'
      ? viewport.getCurrentImageIdIndex()
      : 0;

  let next = current + direction;

  if (next >= totalImages) {
    direction = -1;
    next = totalImages - 2;
  } else if (next < 0) {
    direction = 1;
    next = 1;
  }

  next = Math.max(0, Math.min(next, totalImages - 1));

  if (typeof viewport.setImageIdIndex === 'function') {
    viewport.setImageIdIndex(next);
  }

  scheduleViewportReport(viewport, currentSeries, sliceOverlayElement);
}

/**
 * Start cine playback.
 *
 * @param {object}           viewport
 * @param {object|null}      currentSeries
 * @param {HTMLElement|null} sliceOverlayElement
 * @param {number}           [requestedFps]
 */
export function startCine(viewport, currentSeries, sliceOverlayElement, requestedFps) {
  stopCine();
  if (typeof requestedFps === 'number' && requestedFps > 0) {
    fps = requestedFps;
  }
  playing = true;
  const interval = Math.max(16, Math.round(1000 / fps));
  cineTimer = setInterval(() => {
    runCineLoop(viewport, currentSeries, sliceOverlayElement);
  }, interval);
}

/**
 * Stop cine playback.
 */
export function stopCine() {
  clearCineTimer();
  playing = false;
  direction = 1;
}

/**
 * Update the playback speed (FPS).
 *
 * @param {number}           newFps
 * @param {object}           viewport
 * @param {object|null}      currentSeries
 * @param {HTMLElement|null} sliceOverlayElement
 */
export function setCineSpeed(newFps, viewport, currentSeries, sliceOverlayElement) {
  if (typeof newFps !== 'number' || newFps <= 0) {
    return;
  }
  fps = newFps;
  if (playing) {
    startCine(viewport, currentSeries, sliceOverlayElement, fps);
  }
}

/**
 * Whether cine is currently playing.
 * @returns {boolean}
 */
export function isCinePlaying() {
  return playing;
}
