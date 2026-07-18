(function () {
// Ported from https://github.com/Taknok/youtube-auto-like (MIT).
const POLL_INTERVAL = 1000;

// Like this many seconds before the end, else a replay resets currentTime first.
const END_MARGIN = 2;

let timeoutId = 0;
// Set once we've decided like/skip for the current video; blocks retrigger.
let decided = false;

function stop() {
    clearTimeout(timeoutId);
    timeoutId = 0;
}

function getPlayer() {
    const player = document.getElementById('movie_player');
    const video = player?.querySelector('video');
    if (player && video?.clientWidth) return { player, video };
}

function getButtons() {
    const actions = document.querySelector('ytd-menu-renderer.ytd-watch-metadata segmented-like-dislike-button-view-model');
    return {
        like: actions?.querySelector('like-button-view-model button'),
        dislike: actions?.querySelector('dislike-button-view-model button')
    };
}

function isRated(like, dislike) {
    return like?.getAttribute('aria-pressed') == 'true' || dislike?.getAttribute('aria-pressed') == 'true';
}

function isLive() {
    return !!document.querySelector('.ytp-live-badge[disabled=""]');
}

function isAdShowing(player) {
    return /ad-showing|ad-interrupting/.test(player.className);
}

function isSubscribed() {
    const button = document.querySelector('ytd-watch-metadata ytd-subscribe-button-renderer');
    return !!(button?.subscribed || button?.hasAttribute('subscribed'));
}

function getChannel() {
    try { return navigator.mediaSession.metadata.artist }
    catch { return '' }
}

ytTweaks.tweaks.push(function (settings) {
    if (!settings.autoLike || window.top != window) return;

    function minutesThreshold() {
        return (settings.autoLikeMinutes ?? 10) * 60;
    }

    function channelAllowed() {
        if (!settings.autoLikeFilterChannels) return true;

        const list = settings.autoLikeChannels;
        if (!list?.length) return true;

        const listed = list.includes(getChannel());
        return settings.autoLikeChannelsMode == 'only' ? listed : !listed;
    }

    // Only called once watched-enough, so a late subscribe/metadata still counts.
    function shouldLike() {
        if (!channelAllowed()) return false;
        return settings.autoLike == 'all' || isSubscribed();
    }

    function isWatchedEnough(video) {
        const when = settings.autoLikeWhen;
        if (when == 'instant') return true;

        // A live stream has no duration to take a percentage of; only minutes apply.
        if (isLive()) return when == 'minutes' && video.currentTime >= minutesThreshold();

        if (!video.duration || isNaN(video.duration)) return false;

        const likeTime = when == 'minutes' ? minutesThreshold() : video.duration * (settings.autoLikePercent ?? 50) / 100;
        return video.currentTime >= Math.min(likeTime, video.duration - END_MARGIN);
    }

    function tick() {
        timeoutId = 0;
        if (decided) return;

        const { like, dislike } = getButtons();

        // No button = metadata not rendered yet (not a 'no').
        if (!like) return reschedule();

        if (isRated(like, dislike)) {
            decided = true;
            return;
        }

        const target = getPlayer();

        // No player yet, or an ad is showing; ads have their own like/dislike state.
        if (!target || isAdShowing(target.player)) return reschedule();

        if (!isWatchedEnough(target.video)) return reschedule();

        decided = true;
        if (shouldLike()) like.click();
    }

    function reschedule() {
        timeoutId = setTimeout(tick, POLL_INTERVAL);
    }

    function start() {
        stop();
        decided = false;

        if (location.pathname.startsWith('/watch')) reschedule();
    }

    // The watch page is never reloaded between videos, so re-arm on nav.
    document.addEventListener('yt-navigate-finish', start);
    start();

    ytTweaks.autoLike = {
        storageChanged: function () {
            document.removeEventListener('yt-navigate-finish', start);
            stop();
        }
    };
});
})();
