package app.yahagi.kancollebrowser.browser

internal object GameFrameRateBridgeScript {
    const val objectName = "YahagiFrameRate"

    val source: String =
        """
        (() => {
          'use strict';
          if (window.__yahagiFrameRateBridgeInstalled) return;
          const bridge = window.YahagiFrameRate;
          if (!bridge || typeof bridge.postMessage !== 'function') return;
          window.__yahagiFrameRateBridgeInstalled = true;

          let target = 'fps60';
          let disposed = false;
          let tickerState = null;
          let mainCanvas = null;
          let renderedCanvas = null;
          let meterRAF = null;
          const renderHooks = [];
          const maxSamples = 512;
          const now = () => window.performance.now();
          const visible = () => !document.hidden && document.visibilityState !== 'hidden';
          const gameDocument = () => window.location.pathname === '/kcs2' ||
            window.location.pathname.indexOf('/kcs2/') === 0;
          const ticker = () => window.createjs && window.createjs.Ticker;
          const cap = () => target === 'highRefresh' ? null : target === 'fps30' ? 30 : 60;
          const positive = value => Number.isFinite(value) && value > 0;
          const approximately = (a, b) => Math.abs(a - b) < 0.001;

          // Keep the phase remainder. The stock 0.6.2 check discards it, reducing
          // a 60 Hz target to 45 ticks at 90 Hz and 48 ticks at 144 Hz.
          const cadence = () => ({next: null, last: null, period: null});
          const resetCadence = state => { state.next = state.last = state.period = null; };
          const due = (state, time, period) => {
            if (state.period !== period || state.last === null || time < state.last ||
                time - state.last > Math.max(250, period * 4)) {
              state.next = time;
            }
            state.period = period;
            state.last = time;
            const epsilon = 0.001;
            if (time + epsilon < state.next) return false;
            const elapsed = Math.max(0, time - state.next);
            state.next += (Math.floor((elapsed + epsilon) / period) + 1) * period;
            return true;
          };
          const renderCadence = cadence();
          let sampleStart = now();
          let rafFrames = 0;
          let renderFrames = 0;
          let lastRenderAt = null;
          let renderIntervals = [];
          let renderCpu = [];
          let lastSample = null;
          const resetWindow = (resetGap) => {
            sampleStart = now();
            rafFrames = renderFrames = 0;
            renderIntervals = [];
            renderCpu = [];
            if (resetGap) lastRenderAt = null;
          };
          const pushBounded = (values, value) => {
            if (values.length < maxSamples && Number.isFinite(value) && value >= 0) values.push(value);
          };
          const percentile = (values, fraction) => {
            if (!values.length) return null;
            const ordered = values.slice().sort((a, b) => a - b);
            return ordered[Math.min(ordered.length - 1, Math.ceil(ordered.length * fraction) - 1)];
          };

          const restoreTicker = () => {
            if (!tickerState) return;
            if (tickerState.ticker._handleSynch === tickerState.wrapper) {
              tickerState.ticker._handleSynch = tickerState.original;
            }
            if (tickerState.ticker.timingMode === tickerState.lastMode) {
              tickerState.ticker.timingMode = tickerState.initialMode;
            }
            if (tickerState.lastApplied !== null &&
                approximately(Number(tickerState.ticker.framerate), tickerState.lastApplied) &&
                positive(tickerState.initialFps)) tickerState.ticker.framerate = tickerState.initialFps;
            tickerState = null;
          };
          const ensureTicker = (changed) => {
            const current = ticker();
            if (!current) { restoreTicker(); return false; }
            if (!tickerState || tickerState.ticker !== current) {
              restoreTicker();
              const state = {ticker: current, original: current._handleSynch,
                wrapper: null, cadence: cadence(), lastApplied: null, startTime: current._startTime,
                initialMode: current.timingMode, initialFps: Number(current.framerate), lastMode: null};
              const compatible = ['_handleSynch', '_setupTick', '_getTime', '_tick']
                .every(key => typeof current[key] === 'function') &&
                positive(Number(current._interval)) && Number.isFinite(current._lastTime) &&
                typeof current.RAF_SYNCHED !== 'undefined';
              if (compatible) {
                state.wrapper = function() {
                  if (disposed || tickerState !== state || current.timingMode !== current.RAF_SYNCHED) {
                    return state.original.apply(this, arguments);
                  }
                  current._timerId = null;
                  current._setupTick();
                  if (state.startTime !== current._startTime) {
                    state.startTime = current._startTime;
                    resetCadence(state.cadence);
                  }
                  const interval = Number(current._interval);
                  if (positive(interval) && due(state.cadence, current._getTime(), interval)) current._tick();
                };
                current._handleSynch = state.wrapper;
              }
              tickerState = state;
              changed = true;
            }
            const state = tickerState;
            const configured = Number(current.framerate);
            if (target === 'highRefresh') {
              // RAF ignores framerate for scheduling, but game animation code
              // reads it when constructing velocity/animationSpeed parameters.
              if (changed && !approximately(configured, 60)) current.framerate = 60;
              if (changed) state.lastApplied = 60;
              if (typeof current.RAF !== 'undefined') current.timingMode = current.RAF;
            } else {
              const limit = cap();
              // A game-owned lower rate is an intentional slowdown. Do not keep
              // undoing it: some game code caches setFPS and will not write twice.
              const desired = changed ? limit : positive(configured) ? Math.min(limit, configured) : limit;
              if (!approximately(configured, desired)) {
                current.framerate = desired;
                state.lastApplied = desired;
              } else if (changed) state.lastApplied = desired;
              current.timingMode = state.wrapper && current._handleSynch === state.wrapper
                ? current.RAF_SYNCHED : current.TIMEOUT;
            }
            state.lastMode = current.timingMode;
            if (changed) resetCadence(state.cadence);
            return true;
          };

          const instrumented = () => gameDocument() && !!ticker() && !!window.PIXI &&
            !!mainCanvas && mainCanvas.isConnected !== false && renderHooks.length > 0;
          const meter = () => {
            meterRAF = null;
            if (disposed || !visible() || !instrumented()) return;
            rafFrames++;
            meterRAF = window.requestAnimationFrame(meter);
          };
          const syncMeter = () => {
            if (!visible() || !instrumented()) {
              if (meterRAF !== null) window.cancelAnimationFrame(meterRAF);
              meterRAF = null;
            } else if (meterRAF === null) {
              resetWindow(true);
              meterRAF = window.requestAnimationFrame(meter);
            }
          };
          const ensureRenderers = () => {
            if (!gameDocument() || !window.PIXI) return;
            const canvas = document.querySelector('canvas');
            if (canvas !== mainCanvas) {
              mainCanvas = canvas;
              renderedCanvas = null;
              resetCadence(renderCadence);
              resetWindow(true);
            }
            for (const key of ['WebGLRenderer', 'CanvasRenderer']) {
              const proto = window.PIXI[key] && window.PIXI[key].prototype;
              if (!proto || typeof proto.render !== 'function' ||
                  renderHooks.some(hook => hook.proto === proto || hook.wrapper === proto.render)) continue;
              const descriptor = Object.getOwnPropertyDescriptor(proto, 'render');
              const original = proto.render;
              const wrapper = function(stage, renderTexture) {
                if (disposed || renderTexture != null || this.view !== mainCanvas || !instrumented()) {
                  return original.apply(this, arguments);
                }
                const started = now();
                const limit = cap();
                if (limit !== null && !due(renderCadence, started, 1000 / limit)) return;
                const result = original.apply(this, arguments);
                renderedCanvas = mainCanvas;
                if (visible()) {
                  if (lastRenderAt !== null) pushBounded(renderIntervals, started - lastRenderAt);
                  lastRenderAt = started;
                  renderFrames++;
                  pushBounded(renderCpu, now() - started);
                }
                return result;
              };
              try {
                proto.render = wrapper;
                if (proto.render === wrapper) renderHooks.push({proto, descriptor, original, wrapper});
              } catch (_) {}
            }
          };
          const refresh = (changed) => {
            if (disposed) return;
            ensureTicker(changed);
            ensureRenderers();
            syncMeter();
          };
          const post = value => { try { bridge.postMessage(JSON.stringify(value)); } catch (_) {} };
          const sample = () => {
            refresh(false);
            // Gadget/DMM frames share the bridge but must never overwrite a
            // game frame's measurements with missing instrumentation.
            if (!gameDocument() || !ticker()) return;
            const duration = now() - sampleStart;
            if (duration < 250) return;
            const current = ticker();
            let fps = null;
            if (current && typeof current.getMeasuredFPS === 'function') {
              const measured = Number(current.getMeasuredFPS());
              if (Number.isFinite(measured) && measured >= 0) fps = measured;
            }
            const measured = visible() && instrumented();
            const rendered = measured && renderedCanvas === mainCanvas;
            const configured = current && Number(current.framerate);
            lastSample = {kind: 'sample', fps: fps,
              rafFps: measured ? rafFrames * 1000 / duration : null,
              renderFps: rendered ? renderFrames * 1000 / duration : null,
              renderP95Ms: rendered ? percentile(renderIntervals, 0.95) : null,
              renderP99Ms: rendered ? percentile(renderIntervals, 0.99) : null,
              renderCpuP95Ms: rendered ? percentile(renderCpu, 0.95) : null,
              pixiVersion: window.PIXI && typeof window.PIXI.VERSION === 'string' ? window.PIXI.VERSION : null,
              configuredFps: positive(configured) ? Math.round(configured * 1000) / 1000 : null,
              target: target, visible: visible(), sampleDurationMs: duration, sampledAtMs: now(),
              renderFrames: rendered ? renderFrames : null};
            post(lastSample);
            resetWindow(false);
          };
          const onMessage = event => {
            try {
              const data = typeof event.data === 'string' ? JSON.parse(event.data) : event.data;
              if (!data || !['fps30', 'fps60', 'highRefresh'].includes(data.target)) return;
              const changed = target !== data.target;
              target = data.target;
              if (changed) { resetCadence(renderCadence); resetWindow(true); }
              refresh(changed);
            } catch (_) {}
          };
          const onVisibility = () => {
            resetCadence(renderCadence);
            if (tickerState) resetCadence(tickerState.cadence);
            resetWindow(true);
            syncMeter();
          };
          const previousOnMessage = bridge.onmessage;
          bridge.onmessage = onMessage;
          document.addEventListener('visibilitychange', onVisibility);
          const intervalId = window.setInterval(sample, 1000);
          window.__yahagiFrameRateRuntime = {
            getSnapshot: () => lastSample ? Object.assign({}, lastSample) : null,
            dispose: () => {
            if (disposed) return;
            disposed = true;
            window.clearInterval(intervalId);
            if (meterRAF !== null) window.cancelAnimationFrame(meterRAF);
            meterRAF = null;
            document.removeEventListener('visibilitychange', onVisibility);
            if (bridge.onmessage === onMessage) bridge.onmessage = previousOnMessage;
            restoreTicker();
            for (const hook of renderHooks) {
              if (hook.proto.render !== hook.wrapper) continue;
              if (hook.descriptor) Object.defineProperty(hook.proto, 'render', hook.descriptor);
              else delete hook.proto.render;
            }
            delete window.__yahagiFrameRateBridgeInstalled;
            delete window.__yahagiFrameRateRuntime;
          }};
          refresh(false);
          post({kind: 'ready'});
        })();
        """.trimIndent()
}
