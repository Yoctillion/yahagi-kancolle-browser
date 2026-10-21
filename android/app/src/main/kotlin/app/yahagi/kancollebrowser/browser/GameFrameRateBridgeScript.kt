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
          let foreground = true;
          let foregroundKnown = false;
          let documentActive = true;
          let resumeTimer = null;
          let resumeEpoch = 0;
          let resumeObservation = null;
          let observedTicker = null;
          let observedPaused = null;
          let tickerState = null;
          let mainCanvas = null;
          let renderedCanvas = null;
          let meterRAF = null;
          const renderHooks = [];
          const maxSamples = 512;
          const now = () => window.performance.now();
          const visible = () => !document.hidden && document.visibilityState !== 'hidden';
          const active = () => documentActive && foreground && visible();
          const gameDocument = () => window.location.pathname === '/kcs2' ||
            window.location.pathname.indexOf('/kcs2/') === 0;
          const ticker = () => window.createjs && window.createjs.Ticker;
          const cap = () => target === 'highRefresh' ? null : target === 'fps30' ? 30 : 60;
          const positive = value => Number.isFinite(value) && value > 0;
          const approximately = (a, b) => Math.abs(a - b) < 0.001;
          const tickCount = current => {
            if (!current || typeof current.getTicks !== 'function') return null;
            const value = Number(current.getTicks());
            return Number.isFinite(value) ? value : null;
          };

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
          let sampleTicker = ticker();
          let sampleTickCount = tickCount(sampleTicker);
          const resetWindow = (resetGap) => {
            sampleStart = now();
            rafFrames = renderFrames = 0;
            renderIntervals = [];
            renderCpu = [];
            sampleTicker = ticker();
            sampleTickCount = tickCount(sampleTicker);
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
          const applyFrameRate = (state, value) => {
            state.applyingFPS = true;
            try {
              state.ticker.framerate = value;
              state.lastApplied = value;
            } finally {
              state.applyingFPS = false;
              state.lastConfigured = Number(state.ticker.framerate);
            }
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
                approximately(Number(tickerState.ticker.framerate), tickerState.lastApplied)) {
              const restored = tickerState.gameFps === null ? tickerState.initialFps : tickerState.gameFps;
              if (positive(restored)) applyFrameRate(tickerState, restored);
            }
            if (tickerState.ticker.setFPS === tickerState.fpsObserver) {
              tickerState.ticker.setFPS = tickerState.originalSetFPS;
            }
            tickerState = null;
          };
          const ensureTicker = (changed, preserveGameRate) => {
            const current = ticker();
            if (!current) { restoreTicker(); return false; }
            if (!tickerState || tickerState.ticker !== current) {
              restoreTicker();
              const state = {ticker: current, original: current._handleSynch,
                wrapper: null, cadence: cadence(), lastApplied: null, startTime: current._startTime,
                initialMode: current.timingMode, initialFps: Number(current.framerate), lastMode: null,
                originalSetFPS: current.setFPS, fpsObserver: null, applyingFPS: false,
                gameFps: null, lastConfigured: Number(current.framerate)};
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
              if (typeof state.originalSetFPS === 'function') {
                state.fpsObserver = function(value) {
                  const result = state.originalSetFPS.apply(this, arguments);
                  if (!state.applyingFPS && tickerState === state) {
                    try {
                      const applied = Number(current.framerate);
                      if (positive(applied)) {
                        state.gameFps = applied;
                        state.lastConfigured = applied;
                        if (target === 'highRefresh') ensureTicker(false, true);
                      }
                    } catch (_) {}
                  }
                  return result;
                };
                try { current.setFPS = state.fpsObserver; } catch (_) {}
              }
              changed = true;
            }
            const state = tickerState;
            const configured = Number(current.framerate);
            if (positive(configured) && !approximately(configured, state.lastConfigured)) {
              state.gameFps = configured;
            }
            if (changed && !preserveGameRate) state.gameFps = null;
            if (target === 'highRefresh') {
              // RAF ignores framerate for scheduling, but game animation code
              // reads it when constructing velocity/animationSpeed parameters.
              const desired = preserveGameRate && state.gameFps !== null ? state.gameFps : 60;
              if (changed && !approximately(configured, desired)) applyFrameRate(state, desired);
              if (state.gameFps !== null && state.gameFps < 60 && !approximately(state.gameFps, 60)) {
                current.timingMode = state.wrapper && current._handleSynch === state.wrapper
                  ? current.RAF_SYNCHED : current.TIMEOUT;
              } else if (typeof current.RAF !== 'undefined') current.timingMode = current.RAF;
            } else {
              const limit = cap();
              // A game-owned lower rate is an intentional slowdown. Do not keep
              // undoing it: some game code caches setFPS and will not write twice.
              const desired = preserveGameRate && state.gameFps !== null ? Math.min(limit, state.gameFps)
                : changed ? limit : positive(configured) ? Math.min(limit, configured) : limit;
              if (!approximately(configured, desired)) {
                applyFrameRate(state, desired);
              }
              current.timingMode = state.wrapper && current._handleSynch === state.wrapper
                ? current.RAF_SYNCHED : current.TIMEOUT;
            }
            state.lastMode = current.timingMode;
            state.lastConfigured = Number(current.framerate);
            if (changed) resetCadence(state.cadence);
            return true;
          };

          const cancelResumeTimer = () => {
            resumeEpoch++;
            if (resumeTimer !== null) window.clearTimeout(resumeTimer);
            resumeTimer = null;
          };
          const cancelResumeCheck = () => {
            cancelResumeTimer();
            resumeObservation = null;
          };
          const canObserve = current => active() && gameDocument() && current &&
            current._inited === true &&
            typeof current.hasEventListener === 'function' && current.hasEventListener('tick') &&
            typeof current._setupTick === 'function' && positive(Number(current._interval)) &&
            Number.isFinite(current._lastTime) && tickCount(current) !== null;
          const observeResume = () => {
            const observation = resumeObservation;
            if (!observation) return;
            if (disposed || !active() || now() >= observation.expiresAt) {
              cancelResumeCheck();
              return;
            }
            const current = ticker();
            if (observation.ticker !== current ||
                observation.startTime !== (current && current._startTime)) {
              cancelResumeTimer();
              observation.ticker = current;
              observation.startTime = current && current._startTime;
              observation.ticks = tickCount(current);
            }
            if (!canObserve(current)) return;
            if (observation.ticks !== null && tickCount(current) > observation.ticks) {
              cancelResumeCheck();
              return;
            }
            if (current.paused === true || resumeTimer !== null) return;
            const ticks = tickCount(current), lastTime = current._lastTime;
            const startTime = current._startTime, timerId = current._timerId;
            const delay = Math.max(1000, Number(current._interval) * 3);
            if (!Number.isFinite(delay) || now() + delay > observation.expiresAt) return;
            const epoch = resumeEpoch, started = now();
            resumeTimer = window.setTimeout(() => {
              if (epoch !== resumeEpoch) return;
              resumeTimer = null;
              if (disposed || !active() || now() >= observation.expiresAt) {
                cancelResumeCheck();
                return;
              }
              if (ticker() !== current || !canObserve(current) ||
                  current._startTime !== startTime) return;
              if (tickCount(current) !== ticks || current._lastTime !== lastTime) {
                cancelResumeCheck();
                return;
              }
              if (current.paused === true || current._timerId !== timerId ||
                  now() - started + 0.001 < Math.max(1000, Number(current._interval) * 3)) return;
              // Resume may leave an id whose browser callback no longer exists.
              // Re-arm only the scheduler; reset() would discard game listeners.
              if (current._timerId != null) {
                if (current._raf) window.cancelAnimationFrame(current._timerId);
                else window.clearTimeout(current._timerId);
              }
              current._timerId = null;
              if (tickerState && tickerState.ticker === current) resetCadence(tickerState.cadence);
              cancelResumeCheck();
              current._setupTick();
            }, delay);
          };
          const checkOnResume = () => {
            cancelResumeCheck();
            if (disposed || !active() || !gameDocument()) return;
            resumeObservation = {expiresAt: now() + 30000, ticker: null, startTime: null, ticks: null};
            observeResume();
          };

          const instrumented = () => gameDocument() && !!ticker() && !!window.PIXI &&
            !!mainCanvas && mainCanvas.isConnected !== false && renderHooks.length > 0;
          const meter = () => {
            meterRAF = null;
            if (disposed || !active() || !instrumented()) return;
            rafFrames++;
            meterRAF = window.requestAnimationFrame(meter);
          };
          const syncMeter = () => {
            if (!active() || !instrumented()) {
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
                if (active()) {
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
          const refresh = (changed, preserveGameRate = true) => {
            if (disposed) return;
            ensureTicker(changed, preserveGameRate);
            ensureRenderers();
            syncMeter();
          };
          const post = value => { try { bridge.postMessage(JSON.stringify(value)); } catch (_) {} };
          const sample = () => {
            refresh(false);
            // Gadget/DMM frames share the bridge but must never overwrite a
            // game frame's measurements with missing instrumentation.
            if (!gameDocument() || !ticker()) return;
            const current = ticker();
            const paused = current.paused === true;
            const unpaused = current === observedTicker && observedPaused === true && !paused;
            observedTicker = current;
            observedPaused = paused;
            // A game may deliberately pause longer than the resume window.
            // Its own unpause edge earns one new check; never change paused.
            if (unpaused && active()) checkOnResume(); else observeResume();
            const duration = now() - sampleStart;
            if (duration < 250) return;
            let fps = null;
            const ticks = tickCount(current);
            const progressed = current === sampleTicker && ticks !== null &&
              sampleTickCount !== null && ticks > sampleTickCount;
            // CreateJS keeps its old FPS history even when no new tick runs.
            if (progressed && typeof current.getMeasuredFPS === 'function') {
              const measured = Number(current.getMeasuredFPS());
              if (Number.isFinite(measured) && measured >= 0) fps = measured;
            }
            const measured = active() && instrumented();
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
              target: target, visible: active(), sampleDurationMs: duration, sampledAtMs: now(),
              renderFrames: rendered ? renderFrames : null};
            post(lastSample);
            resetWindow(false);
          };
          const onMessage = event => {
            try {
              const data = typeof event.data === 'string' ? JSON.parse(event.data) : event.data;
              if (!data || !['fps30', 'fps60', 'highRefresh'].includes(data.target)) return;
              const resumed = data.foreground === true && (!foregroundKnown || !foreground);
              if (typeof data.foreground === 'boolean') {
                foreground = data.foreground;
                foregroundKnown = true;
                if (!foreground) cancelResumeCheck();
              }
              const changed = target !== data.target;
              target = data.target;
              if (changed) { resetCadence(renderCadence); resetWindow(true); }
              refresh(changed, typeof data.foreground === 'boolean');
              if (resumed) checkOnResume();
            } catch (_) {}
          };
          const onVisibility = () => {
            resetCadence(renderCadence);
            if (tickerState) resetCadence(tickerState.cadence);
            resetWindow(true);
            syncMeter();
            if (active()) checkOnResume(); else cancelResumeCheck();
          };
          const onPageHide = () => {
            documentActive = false;
            cancelResumeCheck();
            syncMeter();
          };
          const onPageShow = () => {
            if (disposed) return;
            documentActive = true;
            onVisibility();
          };
          const previousOnMessage = bridge.onmessage;
          bridge.onmessage = onMessage;
          document.addEventListener('visibilitychange', onVisibility);
          window.addEventListener('pagehide', onPageHide);
          window.addEventListener('pageshow', onPageShow);
          const intervalId = window.setInterval(sample, 1000);
          window.__yahagiFrameRateRuntime = {
            getSnapshot: () => lastSample ? Object.assign({}, lastSample) : null,
            dispose: () => {
            if (disposed) return;
            disposed = true;
            cancelResumeCheck();
            window.clearInterval(intervalId);
            if (meterRAF !== null) window.cancelAnimationFrame(meterRAF);
            meterRAF = null;
            document.removeEventListener('visibilitychange', onVisibility);
            window.removeEventListener('pagehide', onPageHide);
            window.removeEventListener('pageshow', onPageShow);
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
