/**
 * viewportState.js — Viewport state extraction and reporting.
 *
 * Reads current viewport properties (zoom, WW/WC, slice index) and
 * emits debounced 'viewport' events to Flutter.
 */

import { emit } from './bridge.js';

const REPORT_DEBOUNCE_MS = 60;

let reportTimer = null;

/**
 * Extract WW/WC from viewport voiRange.
 * @param {object} properties - viewport.getProperties() result.
 * @returns {{ windowWidth: number|null, windowCenter: number|null }}
 */
export function extractWindowLevel(properties) {
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

/**
 * Build the full viewport overlay state from a Cornerstone viewport.
 *
 * @param {object}      viewport       - Cornerstone StackViewport.
 * @param {object|null} currentSeries  - { imageIds: string[] } or null.
 * @param {string|null} statusMessage  - Optional status message to attach.
 * @returns {object|null}
 */
export function buildViewportState(viewport, currentSeries, statusMessage = null) {
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

/**
 * Update the slice overlay DOM element.
 *
 * @param {HTMLElement|null} element
 * @param {number}           currentImageIndex
 * @param {number}           totalImages
 */
export function setSliceOverlay(element, currentImageIndex, totalImages) {
  if (!element) {
    return;
  }

  if (!Number.isFinite(totalImages) || totalImages <= 0) {
    element.textContent = '';
    element.style.display = 'none';
    return;
  }

  const safeCurrent = Math.max(0, Math.min(currentImageIndex, totalImages - 1));
  element.style.display = 'block';
  element.textContent = `Slice: ${safeCurrent + 1} / ${totalImages}`;
}

/**
 * Read current viewport state, update overlay, and emit to Flutter.
 *
 * @param {object}           viewport
 * @param {object|null}      currentSeries
 * @param {HTMLElement|null} sliceOverlayElement
 * @param {string|null}      statusMessage
 */
export function reportViewportState(viewport, currentSeries, sliceOverlayElement, statusMessage = null) {
  const state = buildViewportState(viewport, currentSeries, statusMessage);
  if (!state) {
    return;
  }

  setSliceOverlay(sliceOverlayElement, state.currentImageIndex, state.totalImages);
  emit('viewport', state);
}

/**
 * Schedule a debounced viewport state report.
 *
 * @param {object}           viewport
 * @param {object|null}      currentSeries
 * @param {HTMLElement|null} sliceOverlayElement
 * @param {string|null}      statusMessage
 */
export function scheduleViewportReport(viewport, currentSeries, sliceOverlayElement, statusMessage = null) {
  clearTimeout(reportTimer);
  reportTimer = setTimeout(() => {
    reportViewportState(viewport, currentSeries, sliceOverlayElement, statusMessage);
  }, REPORT_DEBOUNCE_MS);
}
