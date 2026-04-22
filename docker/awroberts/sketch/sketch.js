// sketch.js

import {
  preloadVideoAssets,
  initVideoSystem,
  drawVideo,
  bindVideoP5
} from './video.js';

import {
  preloadUIAssets,
  initUI,
  drawUI,
  handlePointerActivation,
  handleResize,
  bindUIP5
} from './ui.js';

import { getOverlayPixelDensity } from './utils.js';

const sketch = (awrWeb) => {

  // Bind awrWeb instance into modules ONCE
  bindVideoP5(awrWeb);
  bindUIP5(awrWeb);

  awrWeb.preload = () => {
    preloadVideoAssets();
    preloadUIAssets();
  };

  awrWeb.setup = () => {
    awrWeb.pixelDensity(getOverlayPixelDensity());

    const canvas = awrWeb.createCanvas(awrWeb.windowWidth, awrWeb.windowHeight);
    canvas.parent('canvas-container');
    canvas.style('position', 'absolute');
    canvas.style('top', '0');
    canvas.style('left', '0');
    canvas.style('z-index', '1');
    canvas.style('filter', 'saturate(1.8) contrast(1.08)');

    initVideoSystem();
    initUI();
  };

  awrWeb.draw = () => {
    awrWeb.clear();
    drawVideo();
    drawUI();
  };

  awrWeb.mousePressed = () => {
    handlePointerActivation(awrWeb.mouseX, awrWeb.mouseY);
  };

  awrWeb.touchStarted = () => {
    if (awrWeb.touches.length > 0) {
      handlePointerActivation(awrWeb.touches[0].x, awrWeb.touches[0].y);
    }
    return false;
  };

  awrWeb.windowResized = () => {
    awrWeb.resizeCanvas(awrWeb.windowWidth, awrWeb.windowHeight);
    handleResize();
  };
};

new p5(sketch);
