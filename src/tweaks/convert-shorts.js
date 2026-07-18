ytTweaks.tweaks.push(function (settings) {
    // window.top guard: never redirect an embedded Short.
    if (!settings.convertShorts || window.top != window) return;

    const pattern = /^\/shorts\/([\w-]+)/;

    function urlToWatch(raw) {
        const u = new URL(raw, location.origin);
        const id = u.pathname.match(pattern)?.[1];
        if (!id) return;

        // Keep a timestamp; drop the rest, which is Shorts-feed state /watch ignores.
        const time = u.searchParams.get('t');
        return `/watch?v=${id}${time ? `&t=${time}` : ''}`;
    }

    function anchorFromEvent(e) {
        return e.target.closest?.('a[href*="/shorts/"]');
    }

    function navigate(url) {
        const app = document.querySelector('ytd-app');
        // SPA route when possible; fall back to a load before ytd-app is upgraded.
        if (!app?.handleNavigate) {
            location.assign(url);
            return;
        }

        app.handleNavigate({
            command: {
                "commandMetadata": {
                    "webCommandMetadata": {
                        "url": url,
                        "webPageType": "WEB_PAGE_TYPE_WATCH",
                        "rootVe": 3832,
                        "apiUrl": "/youtubei/v1/player"
                    }
                }
            }
        });
    }

    // replace(), not assign(): otherwise Back lands on the Short and bounces again.
    function redirectCurrent() {
        const url = urlToWatch(location.href);
        if (url) location.replace(url);
    }

    function handleClick(e) {
        if (e.button != 0 || e.ctrlKey || e.metaKey || e.shiftKey) return;

        const anchor = anchorFromEvent(e);
        if (!anchor) return;

        const url = urlToWatch(anchor.href);
        if (!url) return;

        // YouTube navigates from renderer data, not the href, so stop its handler.
        e.stopImmediatePropagation();
        e.preventDefault();
        navigate(url);
    }

    // Middle-click / open-in-new-tab read the href directly, bypassing handleClick.
    function handlePointerOver(e) {
        const anchor = anchorFromEvent(e);
        if (!anchor) return;

        const url = urlToWatch(anchor.href);
        if (url) anchor.href = url;
    }

    // yt-navigate-start fires ~4ms in, before the Shorts player mounts (~250ms),
    // and carries the destination while location still points at the old page.
    // Both e.detail.url and e.detail.endpoint... are populated in practice 
    // (confirmed via direct click and history Back/Forward onto a Short).
    function handleNavigateStart(e) {
        const dest = e.detail?.url || e.detail?.endpoint?.commandMetadata?.webCommandMetadata?.url;
        if (!dest) return;

        const url = urlToWatch(dest);
        if (url) navigate(url);
    }

    const listeners = [
        [window, 'click', handleClick, true],
        [window, 'pointerover', handlePointerOver, true],
        [document, 'yt-navigate-start', handleNavigateStart, true],
        // Fallbacks for anything the above misses (Back to a Short, missed navs).
        [window, 'popstate', redirectCurrent],
        [document, 'yt-navigate-finish', redirectCurrent],
    ];
    for (const [target, type, fn, capture] of listeners) target.addEventListener(type, fn, capture);

    redirectCurrent();

    ytTweaks.convertShorts = {
        storageChanged: function () {
            for (const [target, type, fn, capture] of listeners) target.removeEventListener(type, fn, capture);
        }
    };
});
