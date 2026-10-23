/*
 * Voice key table and filename formula from poi-plugin-subtitle.
 * The MIT License (MIT), Copyright (c) 2015 poi contributors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
(function () {
  'use strict';
  if (!/^\/kcs2(?:\/|$)/i.test(location.pathname)) return;
  if (window.__yahagiShipSubtitleRuntime) return;
  var bridge = window.YahagiShipSubtitles;
  if (!bridge || typeof bridge.postMessage !== 'function') return;

  var VOICE_KEYS = [2475, 6547, 1471, 8691, 7847, 3595, 1767, 3311, 2507, 9651, 5321, 4473, 7117, 5947, 9489, 2669, 8741, 6149, 1301, 7297, 2975, 6413, 8391, 9705, 2243, 2091, 4231, 3107, 9499, 4205, 6013, 3393, 6401, 6985, 3683, 9447, 3287, 5181, 7587, 9353, 2135, 4947, 5405, 5223, 9457, 5767, 9265, 8191, 3927, 3061, 2805, 3273, 7331];
  var documentId = (window.crypto && typeof window.crypto.randomUUID === 'function')
    ? window.crypto.randomUUID() : Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);
  var config = { enabled: false, locked: true, fontSize: 'medium', x: 0.5, y: 0.9 };
  var quotes = Object.create(null);
  var files = Object.create(null);
  var decodedFiles = Object.create(null);
  var observed = new Map();
  var wrappers = [];
  var probeTimer = null;
  var probeDelay = 250;
  var timeout = null;
  var pageTimer = null;
  var measureContext = null;
  var resizeObserver = null;
  var observedCanvases = [];
  var canvasObserver = null;
  var canvas = null;
  var root = null;
  var text = null;
  var handle = null;
  var active = null;
  var drag = null;
  var sequence = 0;
  var disposed = false;
  var displayScale = null;
  var running = false;

  function post(message) {
    message.documentId = documentId;
    try { bridge.postMessage(JSON.stringify(message)); } catch (_) { /* A navigation may destroy the channel. */ }
  }
  function finite(value, fallback) {
    return typeof value === 'number' && Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : fallback;
  }
  function clearLine(reposition) {
    sequence++;
    active = null;
    if (timeout !== null) clearTimeout(timeout);
    if (pageTimer !== null) clearTimeout(pageTimer);
    timeout = null;
    pageTimer = null;
    if (text && text.textContent) { text.textContent = ''; text.style.display = 'none'; }
    if (reposition !== false) positionOverlay();
  }
  function bounds() {
    if (canvas && canvas.isConnected) {
      var rect = canvas.getBoundingClientRect();
      if (rect.width > 0 && rect.height > 0) return rect;
    }
    return { left: 0, top: 0, width: window.innerWidth, height: window.innerHeight };
  }
  function findCanvas() {
    var candidates = document.querySelectorAll('canvas');
    var candidatesChanged = candidates.length !== observedCanvases.length;
    var largest = null;
    var area = 0;
    for (var i = 0; i < candidates.length; i++) {
      if (candidates[i] !== observedCanvases[i]) candidatesChanged = true;
      var rect = candidates[i].getBoundingClientRect();
      if (rect.width * rect.height > area) { largest = candidates[i]; area = rect.width * rect.height; }
    }
    canvas = largest;
    if (candidatesChanged) {
      observedCanvases = Array.from(candidates);
      if (resizeObserver) {
        resizeObserver.disconnect();
        observedCanvases.forEach(function (candidate) { resizeObserver.observe(candidate); });
      }
    }
  }
  function layout() {
    if (!root || !config.enabled || document.hidden || (!active && !handle)) return;
    var rect = bounds();
    var scale = Math.max(0.35, Math.min(2.5, rect.width / 1200));
    var sizes = { small: 24, medium: 30, large: 38 };
    // The game keeps a desktop CSS viewport when WebView scales it onto a phone.
    // CSS canvas width alone cannot ensure that subtitles are readable on screen.
    // In an iframe visualViewport.scale stays 1 even when the outer WebView is
    // scaled. Native supplies the actual dp / game CSS pixel ratio in that case.
    var viewportScale = displayScale || (window.visualViewport && Number.isFinite(window.visualViewport.scale) && window.visualViewport.scale > 0
      ? window.visualViewport.scale : 1);
    viewportScale = Math.min(1, viewportScale);
    text.style.fontSize = Math.max(sizes[config.fontSize] * scale, sizes[config.fontSize] * 0.5 / viewportScale) + 'px';
    if (handle) {
      handle.style.width = (30 / viewportScale) + 'px';
      handle.style.height = (24 / viewportScale) + 'px';
      handle.style.fontSize = (20 / viewportScale) + 'px';
      handle.style.lineHeight = (22 / viewportScale) + 'px';
      handle.style.borderRadius = (9 / viewportScale) + 'px';
    }
    text.style.padding = (5 * scale) + 'px ' + (14 * scale) + 'px';
    root.style.maxWidth = Math.max(24, rect.width - 16) + 'px';
    text.style.maxWidth = Math.max(24, Math.min(rect.width - 16, 1040 * scale)) + 'px';
    if (active) {
      var style = getComputedStyle(text);
      var key = [style.fontWeight, style.fontSize, style.fontFamily, style.maxWidth, style.paddingLeft, style.paddingRight].join('|');
      if (active.pagesKey !== key) {
        active.pagesKey = key;
        active.pages = splitPages(active.line, active.prefix, style);
        active.totalWeight = active.pages.reduce(function (sum, page) { return sum + page.weight; }, 0);
      }
      renderPage();
    }
    positionOverlay(rect);
  }
  function positionOverlay(rect, size) {
    if (!root || !config.enabled || document.hidden || (!active && !handle)) return;
    rect = rect || bounds();
    size = size || root.getBoundingClientRect();
    var halfWidth = Math.min(rect.width / 2, size.width / 2);
    var halfHeight = Math.min(rect.height / 2, size.height / 2);
    var x = Math.max(halfWidth, Math.min(rect.width - halfWidth, config.x * rect.width));
    var y = Math.max(halfHeight, Math.min(rect.height - halfHeight, config.y * rect.height));
    root.style.left = (rect.left + x) + 'px';
    root.style.top = (rect.top + y) + 'px';
  }
  function splitPages(line, prefix, style) {
    if (!measureContext) measureContext = document.createElement('canvas').getContext('2d');
    var fontSize = parseFloat(style.fontSize);
    if (measureContext) measureContext.font = style.fontWeight + ' ' + style.fontSize + ' ' + style.fontFamily;
    var width = Math.max(fontSize * 2, parseFloat(style.maxWidth) - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight) - 4);
    var measure = function (value) { return measureContext ? measureContext.measureText(value).width : Array.from(value).length * fontSize; };
    var pages = [];
    var lines = [prefix];
    var weight = 0;
    function flush() { pages.push({ text: lines.join('\n'), weight: Math.max(1, weight) }); lines = [prefix]; weight = 0; }
    Array.from(line).forEach(function (character) {
      var index = lines.length - 1;
      if (character === '\n' || measure(lines[index] + character) > width) {
        if (lines.length === 2) flush();
        else lines.push('');
        index = lines.length - 1;
        if (character === '\n') { weight++; return; }
      }
      lines[index] += character;
      weight++;
    });
    if (weight || !pages.length) flush();
    return pages;
  }
  function renderPage() {
    if (pageTimer !== null) clearTimeout(pageTimer);
    pageTimer = null;
    if (!active || !text || !active.pages || document.hidden) return;
    var pages = active.pages;
    var total = active.totalWeight;
    var elapsed = Math.max(0, performance.now() - active.startedAt);
    // Reserve reading time for short tail pages, within the actual audio budget.
    // When there are too many pages, share that budget equally instead.
    var minimumPageTime = Math.min(600, active.duration / pages.length);
    var weightedTime = Math.max(0, active.duration - minimumPageTime * pages.length);
    var through = 0;
    var pageIndex = pages.length - 1;
    for (var i = 0; i < pages.length; i++) {
      through += minimumPageTime + weightedTime * pages[i].weight / total;
      if (elapsed < through) { pageIndex = i; break; }
    }
    if (text.textContent !== pages[pageIndex].text) text.textContent = pages[pageIndex].text;
    if (text.style.display !== 'block') text.style.display = 'block';
    if (pageIndex < pages.length - 1) {
      var token = active.sequence;
      var delay = Math.max(16, active.startedAt + through - performance.now());
      pageTimer = setTimeout(function () {
        if (active && active.sequence === token && config.enabled && !document.hidden) { renderPage(); positionOverlay(); }
      }, delay);
    }
  }
  function stopDragging(save) {
    if (!drag) return;
    var pointerId = drag.id;
    drag = null;
    try { if (handle && handle.hasPointerCapture(pointerId)) handle.releasePointerCapture(pointerId); } catch (_) { /* Removed or cancelled. */ }
    if (save && config.enabled && !config.locked) post({ kind: 'position', x: config.x, y: config.y });
  }
  function updateHandle() {
    if (!root) return;
    if (config.locked) {
      stopDragging(false);
      if (handle) handle.remove();
      handle = null;
      return;
    }
    if (handle) return;
    handle = document.createElement('button');
    handle.type = 'button';
    handle.setAttribute('data-yahagi-ship-subtitle', 'handle');
    handle.setAttribute('aria-label', '拖动字幕位置');
    handle.textContent = '⠿';
    handle.style.cssText = 'all:initial;box-sizing:border-box;display:block;width:30px;height:24px;border-radius:9px;border:1px solid rgba(255,255,255,.45);background:rgba(0,0,0,.5);color:#fff;font:20px/22px sans-serif;text-align:center;cursor:move;pointer-events:auto;touch-action:none;user-select:none;-webkit-user-select:none;';
    handle.addEventListener('pointerdown', function (event) {
      if (!config.enabled || config.locked || !event.isPrimary || (event.pointerType === 'mouse' && event.button !== 0)) return;
      event.preventDefault(); event.stopPropagation();
      // A longer quote can clamp the visible center away from the saved anchor.
      // Start at that visible center so the first movement always follows the finger.
      var rect = root.getBoundingClientRect();
      drag = { id: event.pointerId, dx: rect.left + rect.width / 2 - event.clientX, dy: rect.top + rect.height / 2 - event.clientY };
      handle.setPointerCapture(event.pointerId);
    });
    handle.addEventListener('pointermove', function (event) {
      if (!drag || drag.id !== event.pointerId) return;
      event.preventDefault(); event.stopPropagation();
      var rect = bounds();
      var size = root.getBoundingClientRect();
      var x = Math.max(size.width / 2, Math.min(rect.width - size.width / 2, event.clientX + drag.dx - rect.left));
      var y = Math.max(size.height / 2, Math.min(rect.height - size.height / 2, event.clientY + drag.dy - rect.top));
      config.x = finite(x / rect.width, config.x);
      config.y = finite(y / rect.height, config.y);
      positionOverlay(rect, size);
    });
    handle.addEventListener('pointerup', function (event) { if (drag && drag.id === event.pointerId) { event.preventDefault(); event.stopPropagation(); stopDragging(true); } });
    handle.addEventListener('pointercancel', function () { stopDragging(false); });
    handle.addEventListener('lostpointercapture', function () { stopDragging(false); });
    handle.addEventListener('click', function (event) { event.preventDefault(); event.stopPropagation(); });
    root.insertBefore(handle, text);
  }
  function ensureOverlay(deferLayout) {
    if (!config.enabled || disposed || document.hidden || !document.documentElement) return;
    if (!root) {
      root = document.createElement('div');
      root.setAttribute('data-yahagi-ship-subtitle', 'root');
      root.style.cssText = 'all:initial;position:fixed;z-index:2147483646;display:flex;flex-direction:column;align-items:center;gap:4px;width:max-content;box-sizing:border-box;transform:translate(-50%,-50%);pointer-events:none;user-select:none;-webkit-user-select:none;';
      text = document.createElement('div');
      text.setAttribute('data-yahagi-ship-subtitle', 'text');
      text.style.cssText = 'all:initial;display:none;box-sizing:border-box;width:max-content;white-space:pre-wrap;overflow-wrap:anywhere;color:#fff;background:rgba(0,0,0,.48);border-radius:5px;font-family:system-ui,"Noto Sans CJK SC",sans-serif;font-weight:600;line-height:1.45;text-align:center;text-shadow:0 1px 2px #000,1px 0 2px #000,-1px 0 2px #000,0 -1px 2px #000;pointer-events:none;user-select:none;-webkit-user-select:none;';
      root.appendChild(text);
      document.documentElement.appendChild(root);
    }
    if (!root.isConnected) document.documentElement.appendChild(root);
    updateHandle();
    if (!deferLayout) layout();
  }
  function identify(src) {
    if (Array.isArray(src)) src = src[0];
    if (typeof src !== 'string') return null;
    var pathname;
    try { pathname = new URL(src, location.href).pathname; } catch (_) { return null; }
    var match = /^\/kcs\/sound\/kc([^/]+)\/(\d+)\.mp3$/i.exec(pathname);
    if (!match) return null;
    var ship = files[match[1]];
    // A voice URL with missing master data still replaces a previous ship line.
    if (!ship) return { missing: true };
    var encoded = Number(match[2]);
    var key = ship.id + ':' + encoded;
    var voiceId = decodedFiles[key];
    if (voiceId === undefined) {
      voiceId = 0;
      if (encoded === 141 || encoded === 241) voiceId = encoded;
      else for (var i = 0; i < VOICE_KEYS.length; i++) {
        if (((ship.id + 7) * 17 * VOICE_KEYS[i]) % 99173 + 100000 === encoded) { voiceId = i + 1; break; }
      }
      decodedFiles[key] = voiceId;
    }
    var entry = quotes[String(ship.id)];
    var line = entry && entry[String(voiceId)];
    return typeof line === 'string' && line.trim() ? { ship: ship, line: line } : { missing: true };
  }
  function onPlay(howl, id) {
    if (!config.enabled || disposed || document.hidden) return;
    var quote = identify(howl._src);
    if (!quote) return;
    clearLine(false);
    if (quote.missing) return;
    if (!canvas || !canvas.isConnected) findCanvas();
    ensureOverlay(true);
    if (!text) return;
    var seconds = 0;
    try { seconds = howl.duration(id); } catch (_) { /* Older Howler builds. */ }
    var knownDuration = Number.isFinite(seconds) && seconds > 0;
    var duration = knownDuration ? seconds * 1000 : Math.max(2500, Math.min(20000, quote.line.length * 180));
    active = { howl: howl, id: id, sequence: sequence, line: quote.line,
      prefix: quote.ship.name ? quote.ship.name + '：' : '', duration: duration, startedAt: performance.now() };
    var thisSequence = sequence;
    // Keep grace only for missing end events; it must not postpone page changes.
    timeout = setTimeout(function () { if (sequence === thisSequence) clearLine(); }, duration + (knownDuration ? 300 : 0));
    layout();
  }
  function onFinish(howl, id) {
    if (active && active.howl === howl && (id === undefined || active.id === id)) clearLine();
  }
  function observe(howl) {
    if (!howl || observed.has(howl) || typeof howl.on !== 'function' || typeof howl.off !== 'function') return;
    var callbacks = { play: function (id) { onPlay(howl, id); } };
    ['end', 'stop', 'pause', 'playerror', 'loaderror'].forEach(function (event) { callbacks[event] = function (id) { onFinish(howl, id); }; });
    Object.keys(callbacks).forEach(function (event) { howl.on(event, callbacks[event]); });
    observed.set(howl, callbacks);
  }
  function installHooks() {
    if (!config.enabled || disposed || document.hidden) return false;
    var proto = window.Howl && window.Howl.prototype;
    if (!proto || typeof proto.play !== 'function') return false;
    function wrap(method, before) {
      if (typeof proto[method] !== 'function' || wrappers.some(function (entry) { return entry.proto === proto && entry.method === method && proto[method] === entry.wrapper; })) return;
      var original = proto[method];
      var wrapper = function () { if (config.enabled && !disposed) before(this); return original.apply(this, arguments); };
      proto[method] = wrapper;
      wrappers.push({ proto: proto, method: method, original: original, wrapper: wrapper });
    }
    wrap('play', observe);
    wrap('unload', function (howl) {
      var callbacks = observed.get(howl);
      if (callbacks) { detach(howl, callbacks); observed.delete(howl); }
      onFinish(howl);
    });
    var howls = window.Howler && window.Howler._howls;
    if (Array.isArray(howls)) howls.forEach(observe);
    return true;
  }
  function probeHooks() {
    if (!config.enabled || disposed || document.hidden) return;
    if (installHooks()) {
      if (probeTimer !== null) clearTimeout(probeTimer);
      probeTimer = null;
      probeDelay = 250;
      return;
    }
    // Only startup without Howler needs a timer. A ready game has no polling.
    if (probeTimer === null) probeTimer = setTimeout(function () {
      probeTimer = null;
      probeDelay = Math.min(1000, probeDelay * 2);
      probeHooks();
    }, probeDelay);
  }
  function suspend() {
    running = false;
    if (probeTimer !== null) clearTimeout(probeTimer);
    probeTimer = null;
    if (resizeObserver) resizeObserver.disconnect();
    if (canvasObserver) canvasObserver.disconnect();
  }
  function detach(howl, callbacks) {
    Object.keys(callbacks).forEach(function (event) { try { howl.off(event, callbacks[event]); } catch (_) { /* An unloaded sound is harmless. */ } });
  }
  function disable() {
    stopDragging(false);
    clearLine();
    suspend();
    observed.forEach(function (callbacks, howl) { detach(howl, callbacks); });
    observed.clear();
    for (var i = wrappers.length - 1; i >= 0; i--) {
      var entry = wrappers[i];
      if (entry.proto[entry.method] === entry.wrapper) entry.proto[entry.method] = entry.original;
    }
    wrappers = [];
    if (resizeObserver) resizeObserver.disconnect();
    resizeObserver = null;
    canvasObserver = null;
    observedCanvases = [];
    canvas = null;
    if (root) root.remove();
    root = text = handle = null;
  }
  function start() {
    if (running || document.hidden || disposed || !document.documentElement) return false;
    running = true;
    if (!resizeObserver && typeof ResizeObserver === 'function') resizeObserver = new ResizeObserver(function () {
      if (!config.enabled || disposed || document.hidden) return;
      findCanvas();
      layout();
    });
    if (!canvasObserver && typeof MutationObserver === 'function') canvasObserver = new MutationObserver(function (records) {
      if (!config.enabled || disposed || document.hidden) return;
      var changed = canvas && !canvas.isConnected;
      function containsCanvas(node) { return node.nodeType === 1 && (node.tagName === 'CANVAS' || node.querySelector('canvas')); }
      for (var i = 0; !changed && i < records.length; i++) {
        var added = records[i].addedNodes;
        var removed = records[i].removedNodes;
        for (var j = 0; j < added.length; j++) if (containsCanvas(added[j])) { changed = true; break; }
        for (var k = 0; !changed && k < removed.length; k++) if (containsCanvas(removed[k])) { changed = true; break; }
      }
      if (changed) { findCanvas(); ensureOverlay(); }
    });
    findCanvas();
    if (resizeObserver) observedCanvases.forEach(function (candidate) { resizeObserver.observe(candidate); });
    if (canvasObserver && document.documentElement) canvasObserver.observe(document.documentElement, { childList: true, subtree: true });
    ensureOverlay();
    probeHooks();
    return true;
  }
  bridge.onmessage = function (event) {
    if (disposed) return;
    var data;
    try { data = typeof event.data === 'string' ? JSON.parse(event.data) : event.data; } catch (_) { return; }
    if (!data || typeof data !== 'object') return;
    if (data.kind === 'config') {
      var previous = [config.locked, config.fontSize, config.x, config.y, displayScale].join('|');
      config.enabled = data.enabled === true;
      if (typeof data.locked === 'boolean') config.locked = data.locked;
      if (['small', 'medium', 'large'].indexOf(data.fontSize) >= 0) config.fontSize = data.fontSize;
      if (typeof data.displayScale === 'number' && Number.isFinite(data.displayScale) && data.displayScale > 0) displayScale = data.displayScale;
      config.x = finite(data.x, config.x); config.y = finite(data.y, config.y);
      if (config.enabled) {
        if (!start() && previous !== [config.locked, config.fontSize, config.x, config.y, displayScale].join('|')) ensureOverlay();
      } else disable();
    } else if (data.kind === 'catalog') {
      quotes = data.quotes && typeof data.quotes === 'object' ? data.quotes : Object.create(null);
      clearLine();
    } else if (data.kind === 'ships' && Array.isArray(data.ships)) {
      files = Object.create(null);
      data.ships.forEach(function (ship) {
        if (Number.isSafeInteger(ship.id) && ship.id > 0 && typeof ship.fileName === 'string' && ship.fileName) {
          files[ship.fileName] = { id: ship.id, name: typeof ship.name === 'string' ? ship.name : '' };
        }
      });
      decodedFiles = Object.create(null);
      clearLine();
    } else if (data.kind === 'dispose') {
      dispose();
    }
  };
  function visibilityChanged() {
    if (document.hidden) { stopDragging(false); clearLine(false); suspend(); }
    else if (config.enabled) start();
  }
  function dispose() {
    if (disposed) return;
    config.enabled = false;
    disable();
    disposed = true;
    document.removeEventListener('visibilitychange', visibilityChanged);
    window.removeEventListener('resize', layout);
    window.removeEventListener('scroll', layout, true);
    if (window.visualViewport) window.visualViewport.removeEventListener('resize', layout);
    post({ kind: 'gone' });
  }
  document.addEventListener('visibilitychange', visibilityChanged);
  document.addEventListener('DOMContentLoaded', function () { if (config.enabled) { start(); probeHooks(); } }, { once: true });
  window.addEventListener('resize', layout);
  window.addEventListener('scroll', layout, true);
  if (window.visualViewport) window.visualViewport.addEventListener('resize', layout);
  window.addEventListener('pagehide', dispose, { once: true });
  window.__yahagiShipSubtitleRuntime = true;
  post({ kind: 'ready', url: location.href, documentStartedAt: performance.timeOrigin || Date.now() - performance.now() });
}());
