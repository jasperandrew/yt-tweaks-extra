(function () {
// YouTube's player API refuses rates outside this range.
const MIN_SPEED = 0.0625;
const MAX_SPEED = 16;

// Reset-click target: the "Default video speed" preference, or 1 when off.
let resetSpeed = 1;
// The rate a reset came from, so a second click restores it.
let previousSpeed = 0;
let step = 0.1;

const label = 'Playback speed';

// Styles are inline, not in the shared stylesheet: on extension disable the
// element survives in YouTube's DOM but an injected <style> would not.
const button = document.createElement('button');
button.className = 'ytp-button yttw-speed-control';
button.setAttribute('aria-label', label);
// .ytp-button pads only its SVG child, so text needs centering itself.
button.style.cssText = `
    display: inline-flex;
    align-items: center;
    justify-content: center;
    box-sizing: border-box;
    height: 100%;
    min-width: 48px;
    padding: 0 6px;
    background: transparent;
    color: #fff;
    font-size: 1.3em;
    font-weight: 500;
    line-height: 1;
    vertical-align: top;
    font-variant-numeric: tabular-nums;
`;

const tooltip = document.createElement('div');
tooltip.className = 'yttw-speed-tooltip';
// createElement, not innerHTML: YouTube enforces Trusted Types.
const tooltipText = document.createElement('div');
tooltipText.className = 'yttw-speed-tooltip-text';
tooltip.append(tooltipText);
// Values from YouTube's www-player.css "delhi-modern" tooltip; 118% font
// inherits the player's scale as a #movie_player child, like the native.
tooltip.style.cssText = `
    position: absolute;
    transform: translateX(-50%);
    pointer-events: none;
    z-index: 1003;
    opacity: 0;
    transition: opacity .1s cubic-bezier(0, 0, .2, 1);
    display: flex;
    align-items: center;
    padding: 5px 9px;
    border-radius: 8px;
    background: var(--yt-sys-color-baseline--overlay-background-medium-light, rgba(0, 0, 0, .3));
    -webkit-backdrop-filter: var(--yt-frosted-glass-backdrop-filter-override, blur(16px));
    backdrop-filter: var(--yt-frosted-glass-backdrop-filter-override, blur(16px));
    color: #fff;
    font-size: 118%;
    font-weight: 500;
    line-height: 15px;
    white-space: nowrap;
    text-shadow: 0 0 2px #000;
`;

function format(speed) {
    return `${+speed.toFixed(2)}x`;
}

function clamp(speed) {
    return Math.min(MAX_SPEED, Math.max(MIN_SPEED, Math.round(speed * 100) / 100));
}

// MIN_SPEED/MAX_SPEED can land off the step grid (e.g. MIN_SPEED = 0.0625).
// Floor/ceil-ing the current grid position before adding the step re-snaps 
// onto the grid from an off-grid value, and is a no-op (equivalent to
// current + dir*step) whenever current is already on it.
function nextStep(current, dir) {
    const steps = (current - 1) / step;
    const grid = dir > 0 ? Math.floor(steps + 1e-6) : Math.ceil(steps - 1e-6);
    return 1 + (grid + dir) * step;
}

function getPlayer() {
    const player = document.getElementById('movie_player');
    const video = player?.querySelector('video');
    if (player && video?.clientWidth) return { player, video };
}

function render(speed) {
    button.textContent = format(speed);
}

function set(speed, target) {
    target ??= getPlayer();
    if (!target) return;

    speed = clamp(speed);

    target.player.setPlaybackRate(speed); // syncs the settings menu
    target.video.playbackRate = speed;    // applies rates the menu has no entry for

    try {
        sessionStorage.setItem('yt-player-playback-rate', JSON.stringify({
            data: speed + '',
            creation: Date.now()
        }));
    } catch { }
}

function handleWheel(e) {
    const target = getPlayer();
    if (!target) return;

    // Stop here: the player's own wheel tweaks capture on the player element.
    e.stopImmediatePropagation();
    e.preventDefault();

    const current = target.video.playbackRate;
    const next = clamp(nextStep(current, e.deltaY < 0 ? 1 : -1));
    if (next == current) return;

    set(next, target);
    positionTooltip(target.player);
}

function handleClick(e) {
    const target = getPlayer();
    if (!target) return;

    e.stopImmediatePropagation();
    e.preventDefault();

    const current = target.video.playbackRate;

    if (current != resetSpeed) {
        previousSpeed = current;
        set(resetSpeed, target);
    }

    else set(previousSpeed || resetSpeed, target);
}

// Follow the video's rate, which the settings menu and hotkeys also change.
function handleRateChange(e) {
    if (e.target.clientWidth) render(e.target.playbackRate);
}

// loadstart fires for every <video>/<audio> on the page (ad creatives, hover
// previews, etc.), not just the main player - skip the rest for everything else.
function handleLoadStart(e) {
    if (e.target.closest('#movie_player')) insert();
}

function showTooltip() {
    tooltipText.textContent = label;
    tooltip.style.opacity = '1';
    positionTooltip();
}

function hideTooltip() {
    tooltip.style.opacity = '0';
}

function positionTooltip(player) {
    player ??= document.getElementById('movie_player');
    if (!player || tooltip.style.opacity != '1') return;

    const buttonRect = button.getBoundingClientRect();
    const playerRect = player.getBoundingClientRect();
    if (!buttonRect.width) return;

    const anchor = player.querySelector('.ytp-progress-bar-container') || player.querySelector('.ytp-chrome-bottom');
    const anchorTop = (anchor?.getBoundingClientRect().top ?? buttonRect.top) - playerRect.top;

    const half = tooltip.offsetWidth / 2;
    const center = buttonRect.left + buttonRect.width / 2 - playerRect.left;

    tooltip.style.left = Math.max(half + 8, Math.min(playerRect.width - half - 8, center)) + 'px';
    tooltip.style.top = (anchorTop - tooltip.offsetHeight - 8) + 'px';
}

function insert() {
    const player = document.getElementById('movie_player');
    const controls = player?.querySelector('.ytp-right-controls');
    if (!controls) return;

    if (controls.contains(button)) return;

    // Remove buttons/tooltips left in the DOM by a previous injection.
    for (const el of controls.querySelectorAll('.yttw-speed-control')) {
        if (el !== button) el.remove();
    }
    for (const el of player.querySelectorAll('.yttw-speed-tooltip')) {
        if (el !== tooltip) el.remove();
    }

    controls.prepend(button);
    player.append(tooltip);

    const target = getPlayer();
    if (target) render(target.video.playbackRate);
}

button.addEventListener('wheel', handleWheel, true);
button.addEventListener('click', handleClick, true);
button.addEventListener('mouseenter', showTooltip);
button.addEventListener('mouseleave', hideTooltip);

ytTweaks.tweaks.push(function (settings) {
    if (!settings.speedControl) {
        button.remove();
        tooltip.remove();
        return;
    }

    step = settings.speedControlStep ?? 0.1;
    resetSpeed = settings.videoSpeed ? settings.vsSpeed ?? 1.5 : 1;

    // Controls are rebuilt when navigating between watch pages.
    document.addEventListener('ratechange', handleRateChange, true);
    document.addEventListener('loadstart', handleLoadStart, true);
    document.addEventListener('yt-navigate-finish', insert);

    insert();

    ytTweaks.speedControl = {
        storageChanged: function () {
            document.removeEventListener('ratechange', handleRateChange, true);
            document.removeEventListener('loadstart', handleLoadStart, true);
            document.removeEventListener('yt-navigate-finish', insert);
        }
    };
});
})();
