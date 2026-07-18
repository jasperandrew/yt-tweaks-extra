(function () {
const EYE_SHOWN = 'M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zM12 17c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5zm0-8c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3z';
const EYE_HIDDEN = 'M12 7c2.76 0 5 2.24 5 5 0 .65-.13 1.26-.36 1.83l2.92 2.92c1.51-1.26 2.7-2.89 3.43-4.75-1.73-4.39-6-7.5-11-7.5-1.4 0-2.74.25-3.98.7l2.16 2.16C10.74 7.13 11.35 7 12 7zM2 4.27l2.28 2.28.46.46C3.08 8.3 1.78 10.02 1 12c1.73 4.39 6 7.5 11 7.5 1.55 0 3.03-.3 4.38-.84l.42.42L19.73 22 21 20.73 3.27 3 2 4.27zM7.53 9.8l1.55 1.55c-.05.21-.08.43-.08.65 0 1.66 1.34 3 3 3 .22 0 .44-.03.65-.08l1.55 1.55c-.67.33-1.41.53-2.2.53-2.76 0-5-2.24-5-5 0-.79.2-1.53.53-2.2zm4.31-.78l3.15 3.15.02-.16c0-1.66-1.34-3-3-3l-.17.01z';

let collapsed = false;
let observer = null;

const button = document.createElement('button');
button.className = 'yttw-comments-toggle';
button.setAttribute('aria-label', 'Toggle comments');
button.title = 'Toggle comments';
button.style.cssText = `
    display: inline-flex;
    align-items: center;
    justify-content: center;
    vertical-align: middle;
    box-sizing: border-box;
    width: 28px;
    height: 28px;
    margin-left: 20px;
    padding: 0;
    border: none;
    border-radius: 50%;
    background: transparent;
    color: #909090;
    cursor: pointer;
`;

const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
svg.setAttribute('viewBox', '0 0 24 24');
svg.setAttribute('width', '24');
svg.setAttribute('height', '24');

const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
path.style.fill = 'currentColor';
svg.append(path);
button.append(svg);

function render() {
    path.setAttribute('d', collapsed ? EYE_HIDDEN : EYE_SHOWN);
    document.documentElement.classList.toggle('yttw-comments-collapsed', collapsed);
    syncColor();
}

// Match the "Sort by" label
function syncColor() {
    const trigger = document.querySelector('ytd-comments#comments ytd-comments-header-renderer #sort-menu #trigger');
    if (trigger) button.style.color = getComputedStyle(trigger).color;
}

// Persist the collapsed state across reloads and videos. yttwSaveSetting
// writes to storage without echoing a change event, so this doesn't re-run every tweak.
function save() {
    document.dispatchEvent(new CustomEvent('yttwSaveSetting', {
        detail: { commentsCollapsed: collapsed }
    }));
}

function toggle() {
    collapsed = !collapsed;
    render();
    save();
}

// Some layouts render the header inside #contents instead of its own #header slot.
// Pull it back out to a sibling position so it's easier to hide the comments alone.
// Because YouTube does dynamic rendering stuff, must run on every mutation, not just at insertion.
function relocateHeader() {
    const header = document.querySelector('ytd-comments#comments ytd-comments-header-renderer');
    const contents = header?.closest('#contents');
    if (contents) contents.before(header);
}

function insert() {
    relocateHeader();

    const sortMenu = document.querySelector('ytd-comments#comments ytd-comments-header-renderer #sort-menu');
    if (!sortMenu) return;

    // Keeps the observer from storming on YouTube's constant comment-DOM churn.
    if (sortMenu.nextElementSibling?.classList.contains('yttw-comments-toggle')) return;

    // Clear any stray/misplaced button, then insert ours.
    for (const el of document.querySelectorAll('.yttw-comments-toggle')) el.remove();
    sortMenu.after(button);
    render();
}

function watch() {
    const comments = document.querySelector('ytd-comments#comments');
    if (comments) observer.observe(comments, { childList: true, subtree: true });
    insert();
}

button.addEventListener('click', toggle);

ytTweaks.tweaks.push(function (settings) {
    if (!settings.commentsToggleButton || window.top != window) {
        button.remove();
        document.documentElement.classList.remove('yttw-comments-collapsed');
        return;
    }

    collapsed = !!settings.commentsCollapsed;

    ytTweaks.sheet.textContent += `
    /* Nudge the native "Sort by" control down so it lines up with the taller comment count and our button. */
    ytd-comments#comments ytd-comments-header-renderer #title #additional-section #sort-menu {
      transform: translateY(3px);
    }

    .yttw-comments-toggle:hover {
      background: rgba(128, 128, 128, .15);
    }

    /* Because YouTube dynamic rendering reasons, collapse the comment list/composer
       to zero height rather than display:none. */
    html.yttw-comments-collapsed ytd-comments#comments ytd-item-section-renderer > #contents,
    html.yttw-comments-collapsed ytd-comments#comments ytd-item-section-renderer > #continuations,
    html.yttw-comments-collapsed ytd-comments#comments ytd-comment-simplebox-renderer {
      max-height: 0 !important;
      overflow: hidden !important;
    }
    `;

    observer = new MutationObserver(insert);
    document.addEventListener('yt-navigate-finish', watch);

    render();
    watch();

    ytTweaks.commentsToggle = {
        storageChanged: function () {
            observer.disconnect();
            document.removeEventListener('yt-navigate-finish', watch);
        }
    };
});
})();
