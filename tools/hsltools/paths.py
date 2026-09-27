"""Repository, content and original-install locations: the single source.

Tracked outputs embed str(path) of some inputs (equipment items.json 'sources',
first-skill manifests), so the table roots are deliberately cwd-relative: every
tool runs from the repository root. ROOT is absolute for tools that build paths
from __file__.
"""
from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / 'tools'
CONTENT = ROOT / 'content'
BATTLES = ROOT / 'content/battles'
IMPORTED = ROOT / 'content/imported'
GENERATED = ROOT / 'content/generated'
EVIDENCE = ROOT / 'docs/evidence_packets'
STATIC_REVERSE = EVIDENCE / 'static_reverse'

# Original text tables (PLAYERS.TXT, ITEM.TXT, MAGIC.TXT, SPECIAL.TXT, TYPE.H, mag-spc.h,
# RANGE.TXT) as imported into the repository; cwd-relative on purpose (see module doc).
TABLES = Path('content/imported/hsl/global/tables')
RESOURCE_TXT = Path('content/imported/hsl/chapter01/source_texts/RESOURCE.TXT')

# The original install lives outside the repository. tools/doctor.sh and
# tools/run_original_hsl.sh honour WINEPREFIX the same way; every tools/hsl_*.py --exe /
# --pak default imports these instead of guessing from $HOME.
#
#   HSL_ORIGINAL_DIR   the folder holding the original data (default WINEPREFIX drive_c/hsl); a Steam
#                      經典版 GAME-PAK folder works as is (its hsl-cn.pak is picked, see below)
#   HSL_ORIGINAL_PAK   the data pack to import (default: hsl-cn.pak when the folder has one — the Steam
#                      folder's hsl.pak is a different data set — else hsl.pak)
#
# When the chosen pack is not <folder>/hsl.pak, ORIGINAL_ROOT is a symlink view under
# ignored/original-view/hsl/ (hsl.pak -> the chosen pack, movie.pak and every non-.pak entry of the folder
# linked as is), so the importers that open hsl.pak next to ORIGINAL_EXE or scan ORIGINAL_ROOT for
# PAKS containers read the chosen pack and nothing else.
WINE_PREFIX = Path(os.environ.get('WINEPREFIX', str(Path.home() / '.wine-hsl-original')))
ORIGINAL_SOURCE_DIR = Path(os.environ.get('HSL_ORIGINAL_DIR') or str(WINE_PREFIX / 'drive_c/hsl')).expanduser()


def _chosen_pak(folder: Path) -> Path:
    explicit = os.environ.get('HSL_ORIGINAL_PAK')
    if explicit:
        return Path(explicit).expanduser()
    return folder / 'hsl-cn.pak' if (folder / 'hsl-cn.pak').is_file() else folder / 'hsl.pak'


def original_view(folder: Path, pak: Path, view: Path = ROOT / 'ignored/original-view/hsl') -> Path:
    """`view` with hsl.pak -> pak plus links to movie.pak and every non-.pak entry of `folder`. It is named
    hsl like the install folder (WINEPREFIX drive_c/hsl): scope_inventory records the PAK folder's basename."""
    view.mkdir(parents=True, exist_ok=True)
    wanted = {'hsl.pak': pak.resolve()}
    for entry in sorted(folder.iterdir()) if folder.is_dir() else ():
        if entry.suffix.lower() == '.pak' and entry.name != 'movie.pak':
            continue  # the data packs: only the chosen one is visible, as hsl.pak
        wanted[entry.name] = entry.resolve()
    for link in view.iterdir():
        if link.is_symlink() and (link.name not in wanted or Path(os.readlink(link)) != wanted[link.name]):
            link.unlink()
    for name, target in wanted.items():
        if not (view / name).is_symlink():
            (view / name).symlink_to(target)
    return view


_PAK = _chosen_pak(ORIGINAL_SOURCE_DIR)
ORIGINAL_ROOT = (original_view(ORIGINAL_SOURCE_DIR, _PAK) if _PAK.is_file() and _PAK != ORIGINAL_SOURCE_DIR / 'hsl.pak'
                 else ORIGINAL_SOURCE_DIR)
ORIGINAL_PAK = ORIGINAL_ROOT / 'hsl.pak'
ORIGINAL_MOVIE_PAK = ORIGINAL_ROOT / 'movie.pak'
ORIGINAL_EXE = ORIGINAL_ROOT / 'hsl01.exe'

# The user-owned Steam 經典版 folder (幻世錄 重製版 app 4030150 ships the 1998 game as GAME-PAK/):
# the only source of the original music\\NN.wav tracks and of the second data pack (hsl.pak = Steam
# default, hsl-cn.pak = the pack our ORIGINAL_PAK matches). Fetch and verify with tools/hsl_steam_classic.py.
# HSL_ORIGINAL_DIR naming a Steam folder (it has music/) is the default.
STEAM_CLASSIC_ROOT = Path(os.environ.get('HSL_STEAM_CLASSIC') or (
    str(ORIGINAL_SOURCE_DIR) if os.environ.get('HSL_ORIGINAL_DIR') and (ORIGINAL_SOURCE_DIR / 'music').is_dir()
    else str(Path.home() / 'hsl-steam/fancy-realm/GAME-PAK'))).expanduser()
