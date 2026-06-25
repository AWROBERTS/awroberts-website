// sketch.js

import {
  preloadVideoAssets,
  initVideoSystem,
  drawBackgroundFallback,
  getVideoFadeAlpha,
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

import { getOverlayPixelDensity, isMobileDevice } from './utils.js';

import {
  initChromaticAberration,
  updateChromaticAberration
} from './chromatic-aberration.js';

import {
  bindScanLinesP5,
  initScanLines,
  updateScanLines,
  drawScanLines,
  handleScanLinesResize
} from './scan-lines.js';

const sketch = (awrWeb) => {

  // Bind p5 instance into modules
  bindVideoP5(awrWeb);
  bindUIP5(awrWeb);
  bindScanLinesP5(awrWeb);

  awrWeb.preload = async () => {
    await preloadVideoAssets();
    await preloadUIAssets();
  };

  awrWeb.setup = () => {
    awrWeb.pixelDensity(getOverlayPixelDensity());

    const canvas = awrWeb.createCanvas(awrWeb.windowWidth, awrWeb.windowHeight);
    canvas.parent('canvas-container');
    canvas.style('position', 'absolute');
    canvas.style('top', '0');
    canvas.style('left', '0');
    canvas.style('z-index', '1');
    // On mobile: skip the multi-pass SVG chromatic aberration filter (expensive GPU op)
    // and cap the frame rate to reduce overall rendering load.
    if (isMobileDevice()) {
      canvas.style('filter', 'saturate(1.8) contrast(1.08)');
      awrWeb.frameRate(30);
    } else {
      canvas.style('filter', 'url(#chromab) saturate(1.8) contrast(1.08)');
    }

    awrWeb.noCursor();

    initChromaticAberration();
    initUI();
    initScanLines();

    // Delay video initialisation until DOM is fully ready
    window.requestAnimationFrame(() => {
      initVideoSystem();
    });
  };

  awrWeb.draw = () => {
    awrWeb.clear();
    // Draw the poster only while the video is loading / fading in.
    // Once the video is at full opacity the gap rows should be black
    // (body background) so scan lines look like CRT dark bands, not frozen
    // poster stripes.
    const fadeAlpha = getVideoFadeAlpha();
    if (fadeAlpha < 1) {
      awrWeb.push();
      awrWeb.tint(255, Math.round(255 * (1 - fadeAlpha)));
      drawBackgroundFallback();
      awrWeb.pop();
    }
    updateScanLines();
    drawScanLines();
    drawUI();
    updateChromaticAberration();
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
    handleScanLinesResize();
  };
};

// Export the sketch — do NOT instantiate p5 here
export default sketch;
