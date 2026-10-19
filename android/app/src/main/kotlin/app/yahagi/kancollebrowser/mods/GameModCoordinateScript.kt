package app.yahagi.kancollebrowser.mods

/** Runs before game code. Only the local view of successful startup data is modified. */
internal object GameModCoordinateScript {
    val allowedOriginRules = setOf("https://*.kancolle-server.com")

    val source: String =
        """
        (() => {
          'use strict';
          if (window.__yahagiModCoordinatesInstalled) return;
          if (location.protocol !== 'https:' ||
              !/^w[0-9]+[a-z]\.kancolle-server\.com$/.test(location.hostname) ||
              (location.port && location.port !== '443')) return;
          const NativeXhr = window.XMLHttpRequest;
          if (typeof NativeXhr !== 'function') return;
          const proto = NativeXhr.prototype;
          const nativeOpen = proto.open;
          const nativeSend = proto.send;
          const textDescriptor = Object.getOwnPropertyDescriptor(proto, 'responseText');
          const responseDescriptor = Object.getOwnPropertyDescriptor(proto, 'response');
          let config;
          try {
            const request = new NativeXhr();
            nativeOpen.call(request, 'GET', '/__yahagi_mods__/coordinates.json', false);
            nativeSend.call(request);
            if (request.status !== 200) return;
            config = JSON.parse(textDescriptor.get.call(request));
          } catch (_) { return; }
          if (!config || !config.ships || !Object.keys(config.ships).length ||
              !Number.isSafeInteger(config.sessionId) || typeof config.token !== 'string') return;
          window.__yahagiModCoordinatesInstalled = true;
          const xhrState = new WeakMap();
          const rawFetch = new WeakMap();
          const knownIds = [...new Set(Object.values(config.ships).flatMap(ship => ship.resourceIds))];
          const report = (resourceIds, failure) => {
            if (!resourceIds.length) return;
            if (resourceIds.length > 256) {
              for (let index = 0; index < resourceIds.length; index += 256) {
                report(resourceIds.slice(index, index + 256), failure);
              }
              return;
            }
            try {
              const request = new NativeXhr();
              nativeOpen.call(request, 'GET', '/__yahagi_mods__/coordinates-report?payload=' +
                encodeURIComponent(JSON.stringify({sessionId: config.sessionId,
                  token: config.token, resourceIds: resourceIds, failure: failure || null})), true);
              nativeSend.call(request);
            } catch (_) {}
          };
          const isStartup = (value) => {
            try {
              const url = new URL(String(value), location.href);
              const current = new URL(location.href);
              return url.origin === current.origin && url.pathname === '/kcsapi/api_start2/getData';
            } catch (_) { return false; }
          };
          const patchObject = (data) => {
            if (!data || data.api_result !== 1 || !data.api_data ||
                !Array.isArray(data.api_data.api_mst_shipgraph)) throw new Error('startup_shape');
            const ships = new Map(data.api_data.api_mst_shipgraph.map(ship => [String(ship.api_id), ship]));
            const applied = [], failed = [];
            for (const [id, selected] of Object.entries(config.ships)) {
              const ship = ships.get(id);
              if (!ship) { failed.push(...selected.resourceIds); continue; }
              for (const [key, value] of Object.entries(selected.graph)) ship[key] = value.slice();
              applied.push(...selected.resourceIds);
            }
            return {data, applied: [...new Set(applied)], failed: [...new Set(failed)]};
          };
          const patchText = (text) => {
            const prefix = text.startsWith('svdata=') ? 'svdata=' : '';
            const result = patchObject(JSON.parse(text.slice(prefix.length)));
            return {...result, text: prefix + JSON.stringify(result.data)};
          };
          const acknowledge = (result) => {
            report(result.applied);
            report(result.failed, 'coordinate_apply_failed');
          };
          // Capture reads raw values dynamically, irrespective of script installation order.
          window.__yahagiModOriginalResponses = Object.freeze({
            xhrText: xhr => textDescriptor.get.call(xhr),
            xhrJson: xhr => responseDescriptor.get.call(xhr),
            fetch: response => rawFetch.get(response) || response,
          });
          const patchedXhr = (xhr) => {
            const state = xhrState.get(xhr);
            if (!state || !state.target || xhr.readyState !== 4 || xhr.status !== 200 ||
                (xhr.responseURL && !isStartup(xhr.responseURL))) return null;
            if (state.done) return state.result;
            state.done = true;
            try {
              let result;
              if (xhr.responseType === 'json') {
                // Never mutate the native object: capture and other consumers retain the original.
                result = patchObject(JSON.parse(JSON.stringify(responseDescriptor.get.call(xhr))));
              } else if (xhr.responseType === '' || xhr.responseType === 'text') {
                result = patchText(textDescriptor.get.call(xhr));
              } else throw new Error('response_type');
              state.result = result;
              acknowledge(result);
            } catch (_) { report(knownIds, 'coordinate_apply_failed'); }
            return state.result;
          };
          try {
            Object.defineProperty(proto, 'responseText', {...textDescriptor, get() {
              const original = textDescriptor.get.call(this);
              return patchedXhr(this)?.text ?? original;
            }});
            Object.defineProperty(proto, 'response', {...responseDescriptor, get() {
              const original = responseDescriptor.get.call(this);
              const result = patchedXhr(this);
              return result ? (this.responseType === 'json' ? result.data : result.text) : original;
            }});
            proto.open = function(method, url, ...rest) {
              const value = nativeOpen.call(this, method, url, ...rest);
              xhrState.set(this, {target: isStartup(url), done: false, result: null});
              return value;
            };
          } catch (_) { report(knownIds, 'coordinate_apply_failed'); }
          if (typeof window.fetch === 'function') {
            const nativeFetch = window.fetch;
            const decorate = (modified, original) => {
              rawFetch.set(modified, original);
              for (const key of ['url', 'redirected', 'type']) {
                Object.defineProperty(modified, key, {value: original[key], configurable: true});
              }
              const clone = modified.clone.bind(modified);
              Object.defineProperty(modified, 'clone', {value: () => decorate(clone(), original.clone())});
              return modified;
            };
            window.fetch = function(...args) {
              const input = args[0];
              const target = isStartup(typeof Request !== 'undefined' && input instanceof Request ? input.url : input);
              return nativeFetch.apply(this, args).then(async response => {
                if (!target || response.status !== 200 || (response.url && !isStartup(response.url))) return response;
                try {
                  const result = patchText(await response.clone().text());
                  const headers = new Headers(response.headers);
                  headers.delete('content-length'); headers.delete('content-encoding');
                  const modified = decorate(new Response(result.text, {status: response.status,
                    statusText: response.statusText, headers}), response);
                  acknowledge(result);
                  return modified;
                } catch (_) { report(knownIds, 'coordinate_apply_failed'); return response; }
              });
            };
          }
        })();
        """.trimIndent()
}
