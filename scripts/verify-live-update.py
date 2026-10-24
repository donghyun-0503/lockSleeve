#!/usr/bin/env python3
"""Re-read the same current frame; assert neither process nor settings restart."""
import json
import os
from pathlib import Path
import subprocess
import time

frames = Path.home() / 'Library/Containers/local.lockalbum.app.wallpaper/Data/Library/Application Support/LockAlbum/Frames'
store = Path.home() / 'Library/Application Support/com.apple.wallpaper/Store/Index.plist'
status = frames / 'renderer-status.json'
before = json.loads(status.read_text())
agent = subprocess.check_output(['pgrep', '-x', 'WallpaperAgent']).strip()
original = store.read_bytes()
filename = 'desktop.png' if before.get('mode') == 'desktop' else 'current.png'
os.utime(frames / filename, None)
for _ in range(30):
    time.sleep(0.2)
    after = json.loads(status.read_text())
    if after['revision'] != before['revision']:
        break
assert after['revision'] != before['revision'], 'Renderer did not reload frame'
assert after['pid'] == before['pid'], 'Renderer restarted'
assert subprocess.check_output(['pgrep', '-x', 'WallpaperAgent']).strip() == agent, 'WallpaperAgent restarted'
assert store.read_bytes() == original, 'Wallpaper settings were rewritten'
assert after['surfaces'] >= 1, 'No active rendering surface'
print(json.dumps({'passed': True, 'rendererPID': after['pid'], 'wallpaperAgentPID': int(agent), 'surfaces': after['surfaces'], 'wallpaperStoreUnchanged': True}, indent=2))
