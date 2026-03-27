/**
 * imageIds.js — Image ID normalization and validation.
 */

const MAX_STACK_SIZE = 3000;

/**
 * Normalize a single DICOM image ID to the `wadouri:` scheme.
 * @param {string} imageId
 * @returns {string}
 */
export function normalizeImageId(imageId) {
  if (typeof imageId !== 'string') {
    return '';
  }

  // Compatibility with old builds that emitted wado-uri: instead of wadouri:
  if (imageId.startsWith('wado-uri:')) {
    return `wadouri:${imageId.substring('wado-uri:'.length)}`;
  }

  return imageId;
}

/**
 * Normalize and validate an array of image IDs.
 * Throws if no valid IDs remain. Caps at MAX_STACK_SIZE.
 *
 * @param {string[]} imageIds
 * @returns {string[]}
 */
export function normalizeImageIds(imageIds) {
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
