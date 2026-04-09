// sketch.js

import { preloadVideoAssets, initVideoSystem, drawVideo } from './video.js';
import { preloadUIAssets, initUI, drawUI, handlePointerActivation, handleResize } from './ui.js';
import { getOverlayPixelDensity } from './utils.js';

export function preload() {
  preloadVideoAssets();
  preloadUIAssets();
}

export function setup() {
  pixelDensity(getOverlayPixelDensity());

  const canvas = createCanvas(windowWidth, windowHeight);
  canvas.parent('canvas-container');
  canvas.style('position', 'absolute');
  canvas.style('top', '0');
  canvas.style('left', '0');
  canvas.style('z-index', '1');
  canvas.style('filter', 'saturate(1.8) contrast(1.08)');

  initVideoSystem();
  initUI();
}

export function draw() {
  clear();
  drawVideo();
  drawUI();
}

export function mousePressed() {
  handlePointerActivation(mouseX, mouseY);
}

export function touchStarted() {
  if (touches.length > 0) {
    handlePointerActivation(touches[0].x, touches[0].y);
  }
  return false;
}

export function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  handleResize();
}
