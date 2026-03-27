/**
 * bridge.js — Flutter ↔ JS communication layer.
 *
 * All messages to Flutter flow through `emit()`.
 * Status pill updates and status events go through `setStatus()`.
 */

/**
 * Send a typed event to the Flutter host via the InAppWebView bridge.
 *
 * @param {string} type   - Event type (e.g. 'ready', 'viewport', 'error').
 * @param {*}      payload - Arbitrary JSON-serializable payload.
 */
export function emit(type, payload) {
  if (window.flutter_inappwebview?.callHandler) {
    window.flutter_inappwebview.callHandler('viewerEvent', { type, payload });
  }
}

/** @type {HTMLElement|null} */
let statusPillElement = null;

/**
 * Bind the status pill DOM element (call once after DOM is ready).
 * @param {HTMLElement|null} element
 */
export function bindStatusPill(element) {
  statusPillElement = element;
}

/**
 * Update the on-screen status pill and emit a 'status' event to Flutter.
 * @param {string} message
 */
export function setStatus(message) {
  if (statusPillElement) {
    statusPillElement.textContent = message;
  }
  emit('status', message);
}
