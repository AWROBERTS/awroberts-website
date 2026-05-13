// sketch.js

import {
  preloadVideoAssets,
  initVideoSystem,
  drawVideo,
  bindVideoP5,
  sampleVideoColor
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

import {
  bindSprayP5,
  initSpray,
  updateSpray,
  drawSpray,
  handleSprayResize
} from './spray.js';

const sketch = (awrWeb) => {

  // Bind p5 instance into modules
  bindVideoP5(awrWeb);
  bindUIP5(awrWeb);
  bindSprayP5(awrWeb);

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

    awrWeb.noCursor();

    initUI();
    initSpray(sampleVideoColor);

    // Delay video initialisation until DOM is fully ready
    window.requestAnimationFrame(() => {
      initVideoSystem();
    });
  };

  awrWeb.draw = () => {
    awrWeb.clear();
    drawVideo();
    updateSpray(awrWeb.mouseX, awrWeb.mouseY, awrWeb.mouseIsPressed);
    drawSpray();
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

  awrWeb.touchMoved = () => {
    if (awrWeb.touches.length > 0) {
      updateSpray(awrWeb.touches[0].x, awrWeb.touches[0].y, true);
    }
    return false;
  };

  awrWeb.windowResized = () => {
    awrWeb.resizeCanvas(awrWeb.windowWidth, awrWeb.windowHeight);
    handleResize();
    handleSprayResize();
  };
};

// Export the sketch — do NOT instantiate p5 here
export default sketch;
