/**
 * loadProgress.js — Series image load progress tracking.
 *
 * Tracks how many images of the current series have been loaded
 * and emits debounced 'imageProgress' events to Flutter.
 */

import { emit } from './bridge.js';

const DEBOUNCE_MS = 100;

/** @type {number} */
let total = 0;
/** @type {number} */
let loaded = 0;
/** @type {string|null} */
let seriesUid = null;
/** @type {Set<string>} */
let imageIdSet = new Set();
/** @type {number|null} */
let debounceTimer = null;

/**
 * Reset progress counters for a new series.
 *
 * @param {string}   uid         - Series instance UID.
 * @param {number}   imageCount  - Total number of images in the series.
 */
export function resetProgress(uid, imageCount) {
  seriesUid = uid;
  total = imageCount;
  loaded = 0;
  imageIdSet = new Set();
  clearTimeout(debounceTimer);
  debounceTimer = null;
}

/**
 * Record that an image finished loading.
 * Emits a debounced 'imageProgress' event if the image belongs to
 * the current series (by checking if its ID is in the tracked set).
 *
 * @param {string}   imageId          - The image ID that was loaded.
 * @param {string[]} seriesImageIds   - Full array of image IDs for the series.
 */
export function recordImage(imageId, seriesImageIds) {
  if (!seriesUid || total === 0) {
    return;
  }

  const normalized = imageId?.replace?.(/^wadouri:/, '') ?? imageId;
  if (imageIdSet.has(normalized)) {
    return;
  }

  const belongs = seriesImageIds?.some(
    (id) => id === imageId || id === normalized || id.replace(/^wadouri:/, '') === normalized,
  );
  if (!belongs) {
    return;
  }

  imageIdSet.add(normalized);
  loaded = imageIdSet.size;

  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(flushProgress, DEBOUNCE_MS);
}

/**
 * Emit the current progress snapshot to Flutter.
 */
function flushProgress() {
  if (!seriesUid) {
    return;
  }

  emit('imageProgress', {
    seriesUid,
    loaded,
    total,
    progress: total > 0 ? loaded / total : 0,
  });
}

/**
 * Get the current progress as a fraction (0-1).
 * @returns {number}
 */
export function getProgress() {
  return total > 0 ? loaded / total : 0;
}
