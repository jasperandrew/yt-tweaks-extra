#!/usr/bin/env bash
# Package src/ into an installable, unsigned .xpi (manifest.json at the archive
# root). Requires Firefox's xpinstall.signatures.required = false to install.
set -euo pipefail
cd "$(dirname "$0")"

python3 - <<'PY'
import zipfile, os
src, out = '../src', '../yt-tweaks.xpi'
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(src):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for f in files:
            if f.startswith('.'):
                continue
            full = os.path.join(root, f)
            z.write(full, os.path.relpath(full, src))
print('built', out)
PY
