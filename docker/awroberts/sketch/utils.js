// utils.js

export function isMobileDevice() {
  return /Mobi|Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
}

export function getOverlayPixelDensity() {
  if (!isMobileDevice()) return 1;
  return Math.min(window.devicePixelRatio || 1, 2);
}
