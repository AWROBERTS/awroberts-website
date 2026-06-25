// utils.js

export function isMobileDevice() {
  return /Mobi|Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
}

export function getOverlayPixelDensity() {
  return 1;
}
