const String gamePageAlignmentScript = r'''
(() => {
  const runtimeVersion = 2;
  if (
    window.__yahagiMobilePresentationRuntimeVersion === runtimeVersion &&
    typeof window.__yahagiMobileSyncPresentation === 'function' &&
    typeof window.__yahagiMobileReadPresentation === 'function'
  ) {
    return window.__yahagiMobileSyncPresentation(true);
  }
  const styleId = '__yahagi_mobile_fixed_canvas__';
  const ooiBrowserStyleId = '__yahagi_mobile_ooi_browser__';
  const ooiBrowserFrameWidth = 1280;
  const ooiBrowserFrameHeight = 800;
  const ooiBrowserGameWidth = 1200;
  const ooiBrowserGameHeight = 720;
  const fixedCanvasCss = `
    html, body {
      margin: 0 !important;
      padding: 0 !important;
      min-width: 1200px !important;
      min-height: 720px !important;
      overflow: hidden !important;
      overscroll-behavior: none !important;
      touch-action: none !important;
    }

    #w,
    #main-ntg {
      position: fixed !important;
      inset: 0 !important;
      z-index: 2147483640 !important;
      width: 1200px !important;
      height: 720px !important;
      margin: 0 !important;
      padding: 0 !important;
    }

    #game_frame,
    #game-container {
      display: block !important;
      width: 1200px !important;
      height: 720px !important;
      position: fixed !important;
      top: 0 !important;
      left: 0 !important;
      z-index: 2147483641 !important;
      margin: 0 !important;
      padding: 0 !important;
      border: 0 !important;
      transform: none !important;
      transform-origin: 0 0 !important;
      overscroll-behavior: none !important;
      touch-action: none !important;
    }

    .naviapp,
    #ntg-recommend,
    #spacing_top,
    aside,
    footer,
    ul:has([aria-label="close"]) {
      display: none !important;
    }
  `;

  const ooiBrowserCss = `
    html,
    body,
    #ooi-page,
    #ooi-content,
    #ooi-game {
      width: 100vw !important;
      height: 100vh !important;
      min-width: 0 !important;
      min-height: 0 !important;
      margin: 0 !important;
      padding: 0 !important;
      overflow: hidden !important;
    }

    #ooi-content,
    #ooi-game {
      display: block !important;
      position: fixed !important;
      inset: 0 !important;
    }

    #ooi-header,
    #ooi-footer,
    #ooi-game > :not(iframe#externalswf) {
      display: none !important;
    }

    #ooi-game > iframe#externalswf {
      display: block !important;
      position: fixed !important;
      left: var(--yahagi-ooi-left, 0px) !important;
      top: var(--yahagi-ooi-top, 0px) !important;
      width: var(--yahagi-ooi-frame-width, 1280px) !important;
      height: var(--yahagi-ooi-frame-height, 800px) !important;
      transform: scale(var(--yahagi-ooi-scale, 1)) !important;
      transform-origin: top left !important;
      margin: 0 !important;
    }
  `;

  const cleanupOoiBrowserPresentation = () => {
    document.getElementById(ooiBrowserStyleId)?.remove();
    const game = document.getElementById('ooi-game');
    game?.style.removeProperty('--yahagi-ooi-frame-width');
    game?.style.removeProperty('--yahagi-ooi-frame-height');
    game?.style.removeProperty('--yahagi-ooi-scale');
    game?.style.removeProperty('--yahagi-ooi-left');
    game?.style.removeProperty('--yahagi-ooi-top');

    if (window.__yahagiMobileOoiResize) {
      window.removeEventListener('resize', window.__yahagiMobileOoiResize);
    }
    if (
      window.__yahagiMobileAlignGame ===
      window.__yahagiMobileOoiAlignGame
    ) {
      delete window.__yahagiMobileAlignGame;
    }
    delete window.__yahagiMobileOoiResize;
    delete window.__yahagiMobileOoiAlignGame;
  };

  const cleanupGamePresentation = () => {
    document.getElementById(styleId)?.remove();

    if (window.__yahagiMobileScrollLock) {
      window.removeEventListener('scroll', window.__yahagiMobileScrollLock);
    }
    if (window.__yahagiMobileAlignGame) {
      window.removeEventListener('load', window.__yahagiMobileAlignGame);
    }

    document.getElementById('game_frame')?.removeAttribute('scrolling');
    delete window.__yahagiMobileScrollLock;
    delete window.__yahagiMobileAlignGame;
  };

  const host = location.hostname.toLowerCase();
  const pathname = location.pathname.toLowerCase();
  const isAccountPage =
    host === 'accounts.dmm.com' || host === 'accounts.dmm.co.jp';
  const isKancolleServerPage =
    host === 'kancolle-server.com' ||
    host.endsWith('.kancolle-server.com');
  const isCurrentDmmGamePage =
    host === 'play.games.dmm.com' &&
    (pathname === '/game/kancolle' || pathname === '/game/kancolle/');
  const isLegacyDmmGamePage =
    (host === 'www.dmm.com' ||
      host === 'dmm.com' ||
      host === 'games.dmm.com') &&
    (pathname === '/netgame/social/-/gadgets/=/app_id=854854' ||
      pathname === '/netgame/social/-/gadgets/=/app_id=854854/');
  const isGamePage =
    isCurrentDmmGamePage ||
    isLegacyDmmGamePage ||
    host === 'osapi.dmm.com' ||
    isKancolleServerPage;
  const isOoiBrowserPage =
    location.hostname === 'ooi.moe' && location.pathname === '/kancolle';

  const isVisibleElement = (element) => {
    if (!element || !element.isConnected) return false;
    const style = getComputedStyle(element);
    if (
      style.display === 'none' ||
      style.visibility === 'hidden' ||
      style.visibility === 'collapse'
    ) {
      return false;
    }
    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  };

  const hasBlockingPageDialog = () =>
    Array.from(document.querySelectorAll('dialog[open]')).some(
      isVisibleElement,
    );

  const hasStandaloneGameCanvas = () =>
    Array.from(document.querySelectorAll('canvas')).some(
      (canvas) =>
        canvas.width === 1200 &&
        canvas.height === 720 &&
        isVisibleElement(canvas),
    );

  const notifyPresentationState = (nextState, forceFit = false) => {
    // Explicit fits must survive both JS and native state deduplication.
    if (forceFit && nextState === 'game') {
      window.__yahagiMobilePresentationState = nextState;
      window.YahagiPresentation?.postMessage('game-fit');
      return;
    }
    if (window.__yahagiMobilePresentationState === nextState) return;
    window.__yahagiMobilePresentationState = nextState;
    if (window.YahagiPresentation) {
      window.YahagiPresentation.postMessage(nextState);
    }
  };

  const applyGamePresentation = () => {
    let style = document.getElementById(styleId);
    if (!style) {
      style = document.createElement('style');
      style.id = styleId;
      document.head.appendChild(style);
    }
    if (style.textContent !== fixedCanvasCss) {
      style.textContent = fixedCanvasCss;
    }

    if (!window.__yahagiMobileAlignGame) {
      window.__yahagiMobileAlignGame = () => {
        window.scrollTo(0, 0);
        if (document.documentElement) document.documentElement.scrollTop = 0;
        if (document.body) document.body.scrollTop = 0;

        const gameFrame = document.getElementById('game_frame');
        if (gameFrame) {
          gameFrame.setAttribute('scrolling', 'no');
          try {
            gameFrame.contentWindow?.scrollTo(0, 0);
          } catch (_) {
            // A cross-origin game frame is still locked by touch-action above.
          }
        }
      };
    }

    if (!window.__yahagiMobileScrollLock) {
      window.__yahagiMobileScrollLock = () => {
        window.__yahagiMobileAlignGame?.();
      };
      window.addEventListener('scroll', window.__yahagiMobileScrollLock, {
        passive: true,
      });
    }

    if (document.readyState === 'complete') {
      window.__yahagiMobileAlignGame();
    } else {
      window.addEventListener('load', window.__yahagiMobileAlignGame);
    }
  };

  const applyOoiBrowserPresentation = () => {
    let style = document.getElementById(ooiBrowserStyleId);
    if (!style) {
      style = document.createElement('style');
      style.id = ooiBrowserStyleId;
      document.head.appendChild(style);
    }
    if (style.textContent !== ooiBrowserCss) {
      style.textContent = ooiBrowserCss;
    }

    if (!window.__yahagiMobileOoiAlignGame) {
      window.__yahagiMobileOoiAlignGame = () => {
        const game = document.getElementById('ooi-game');
        const frame = game?.querySelector('iframe#externalswf');
        if (!game || !frame || !document.documentElement) return;

        const viewportWidth = Math.max(
          1,
          window.visualViewport?.width || document.documentElement.clientWidth,
        );
        const viewportHeight = Math.max(
          1,
          window.visualViewport?.height || document.documentElement.clientHeight,
        );
        const scale = Math.min(
          1,
          viewportWidth / ooiBrowserGameWidth,
          viewportHeight / ooiBrowserGameHeight,
        );
        const left = Math.max(
          0,
          (viewportWidth - ooiBrowserGameWidth * scale) / 2,
        );
        const top = Math.max(
          0,
          (viewportHeight - ooiBrowserGameHeight * scale) / 2,
        );
        if (game.style.getPropertyValue('--yahagi-ooi-frame-width') !== `${ooiBrowserFrameWidth}px`) {
          game.style.setProperty('--yahagi-ooi-frame-width', `${ooiBrowserFrameWidth}px`);
        }
        if (game.style.getPropertyValue('--yahagi-ooi-frame-height') !== `${ooiBrowserFrameHeight}px`) {
          game.style.setProperty('--yahagi-ooi-frame-height', `${ooiBrowserFrameHeight}px`);
        }
        if (game.style.getPropertyValue('--yahagi-ooi-scale') !== String(scale)) {
          game.style.setProperty('--yahagi-ooi-scale', String(scale));
        }
        if (game.style.getPropertyValue('--yahagi-ooi-left') !== `${left}px`) {
          game.style.setProperty('--yahagi-ooi-left', `${left}px`);
        }
        if (game.style.getPropertyValue('--yahagi-ooi-top') !== `${top}px`) {
          game.style.setProperty('--yahagi-ooi-top', `${top}px`);
        }
      };
    }
    window.__yahagiMobileAlignGame = window.__yahagiMobileOoiAlignGame;

    window.__yahagiMobileOoiAlignGame();
  };

  let scheduledFrame = null;
  let scheduledTimer = null;
  const cancelScheduledSync = () => {
    if (scheduledFrame !== null) {
      window.cancelAnimationFrame?.(scheduledFrame);
      scheduledFrame = null;
    }
    if (scheduledTimer !== null) {
      clearTimeout(scheduledTimer);
      scheduledTimer = null;
    }
  };
  const scheduleSync = () => {
    if (scheduledFrame !== null || scheduledTimer !== null) return;
    const synchronize = () => {
      cancelScheduledSync();
      window.__yahagiMobileSyncPresentation();
    };
    // Animation frames may pause in a hidden/folding WebView. Bound that wait.
    scheduledTimer = setTimeout(synchronize, 100);
    if (typeof window.requestAnimationFrame === 'function') {
      scheduledFrame = window.requestAnimationFrame(synchronize);
    }
  };

  const readPresentation = () => {
    if (!document.documentElement || !document.head || !document.body) {
      return {state: isGamePage && !isAccountPage ? 'pending' : 'web', unparsed: true};
    }
    const hasOoiBrowserSurface = isOoiBrowserPage && Boolean(
      document.querySelector('#ooi-page #ooi-game > iframe#externalswf'),
    );
    if (isOoiBrowserPage && hasOoiBrowserSurface) {
      return {state: 'web', ooi: true};
    }

    if (!isGamePage || isAccountPage || hasBlockingPageDialog()) {
      return {state: 'web'};
    }
    const hasGameSurface =
      Array.from(
        document.querySelectorAll('#game_frame, #game-container'),
      ).some(isVisibleElement) || hasStandaloneGameCanvas();

    return {state: hasGameSurface ? 'game' : 'pending'};
  };
  // Native hints may be queued by an older document. Re-read without fitting
  // or notifying the bridge again, so acknowledgement cannot form a loop.
  window.__yahagiMobileReadPresentation = () => readPresentation().state;

  window.__yahagiMobileSyncPresentation = (forceFit = false) => {
    cancelScheduledSync();
    const presentation = readPresentation();
    if (presentation.unparsed) {
      notifyPresentationState(presentation.state);
      return presentation.state;
    }
    if (presentation.ooi) {
      cleanupGamePresentation();
      applyOoiBrowserPresentation();
      notifyPresentationState('web');
      return 'web';
    }
    cleanupOoiBrowserPresentation();
    if (presentation.state === 'web') {
      cleanupGamePresentation();
      notifyPresentationState('web');
      return 'web';
    }
    if (presentation.state === 'pending') {
      notifyPresentationState('pending');
      return 'pending';
    }

    applyGamePresentation();
    notifyPresentationState('game', forceFit);
    return 'game';
  };

  window.__yahagiMobilePresentationObserver?.disconnect();
  if ((isGamePage && !isAccountPage) || isOoiBrowserPage) {
    window.__yahagiMobilePresentationObserver = new MutationObserver(() => {
      scheduleSync();
    });
    window.__yahagiMobilePresentationObserver.observe(document.documentElement || document, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['class', 'hidden', 'style', 'width', 'height', 'id', 'open'],
    });
    window.addEventListener('resize', scheduleSync, {passive: true});
    window.visualViewport?.addEventListener('resize', scheduleSync, {passive: true});
    document.addEventListener('DOMContentLoaded', scheduleSync, {once: true});
  }

  window.__yahagiMobilePresentationRuntimeVersion = runtimeVersion;
  return window.__yahagiMobileSyncPresentation(true);
})();
''';
