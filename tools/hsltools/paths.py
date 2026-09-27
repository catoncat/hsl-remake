"""Repository, content and original-install locations: the single source.

Tracked outputs embed str(path) of some inputs (equipment items.json 'sources',
first-skill manifests), so the table roots are deliberately cwd-relative: every
tool runs from the repository root. ROOT is absolute for tools that build paths
from __file__.
"""
from __future__ import annotations

import os
import re
import shutil
import sys
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

# The original install lives outside the repository. tools/run_original_hsl.sh honours WINEPREFIX the
# same way; every tools/hsl_*.py --exe / --pak default imports these instead of guessing from $HOME, and
# `python tools/hsl.py doctor` reports which folder was picked and why (ORIGINAL_DIR_ORIGIN).
#
#   HSL_ORIGINAL_DIR   the folder holding the original data; a Steam 經典版 GAME-PAK folder works as is
#                      (its hsl-cn.pak is picked, see below). Unset: detect_original_dir() — Windows and
#                      Linux look for the Steam 經典版 (app 4030150) GAME-PAK folder, macOS and the
#                      fallback everywhere is WINEPREFIX drive_c/hsl
#   HSL_ORIGINAL_PAK   the data pack to import (default: hsl-cn.pak when the folder has one — the Steam
#                      folder's hsl.pak is a different data set — else hsl.pak)
#
# When the chosen pack is not <folder>/hsl.pak, ORIGINAL_ROOT is a symlink view under
# ignored/original-view/hsl/ (hsl.pak -> the chosen pack, movie.pak and every non-.pak entry of the folder
# linked as is), so the importers that open hsl.pak next to ORIGINAL_EXE or scan ORIGINAL_ROOT for
# PAKS containers read the chosen pack and nothing else. Windows without symlink rights (no admin, no
# developer mode) gets junctions for directories and hard links (else copies) for files instead.
WINE_PREFIX = Path(os.environ.get('WINEPREFIX', str(Path.home() / '.wine-hsl-original')))
STEAM_CLASSIC_APP = '4030150'  # 幻世錄 重製版; the 1998 game ships inside it as GAME-PAK/


def _steam_roots() -> list[Path]:
    """Steam installs to search, most specific first (Windows: the SteamPath registry value, then the
    usual folders on C:..F:; Linux: the native, the ~/.steam and the Flatpak install)."""
    roots: list[Path] = []
    if sys.platform == 'win32':
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\Valve\Steam') as key:
                roots.append(Path(winreg.QueryValueEx(key, 'SteamPath')[0]))
        except OSError:
            pass
        for drive in 'CDEF':
            roots += [Path(f'{drive}:/Program Files (x86)/Steam'), Path(f'{drive}:/Program Files/Steam'),
                      Path(f'{drive}:/Steam'), Path(f'{drive}:/SteamLibrary')]
    elif sys.platform.startswith('linux'):
        home = Path.home()
        roots += [home / '.local/share/Steam', home / '.steam/steam', home / '.steam/root',
                  home / '.var/app/com.valvesoftware.Steam/.local/share/Steam']
    return roots


def _steam_libraries(roots: list[Path]) -> list[Path]:
    """Every library folder of those installs (steamapps/libraryfolders.vdf "path" entries), deduplicated."""
    libraries: list[Path] = []
    for root in roots:
        candidates = [root]
        vdf = root / 'steamapps/libraryfolders.vdf'
        if vdf.is_file():
            text = vdf.read_text(encoding='utf-8', errors='replace')
            candidates += [Path(value.replace('\\\\', '\\')) for value in re.findall(r'"path"\s+"([^"]+)"', text)]
        for library in candidates:
            if (library / 'steamapps').is_dir() and all(not _same(library, seen) for seen in libraries):
                libraries.append(library)
    return libraries


def _same(a: Path, b: Path) -> bool:
    try:
        return a.samefile(b)
    except OSError:
        return a == b


def _steam_game_pak(library: Path) -> Path | None:
    """<library>/steamapps/common/<installdir>/GAME-PAK holding a data pack: installdir from the app
    manifest, else any common/ folder with GAME-PAK/hsl-cn.pak (the folder name is not assumed)."""
    manifest = library / f'steamapps/appmanifest_{STEAM_CLASSIC_APP}.acf'
    names: list[str] = []
    if manifest.is_file():
        names += re.findall(r'"installdir"\s+"([^"]+)"', manifest.read_text(encoding='utf-8', errors='replace'))
    common = library / 'steamapps/common'
    folders = [common / name / 'GAME-PAK' for name in names]
    folders += sorted(pak.parent for pak in common.glob('*/GAME-PAK/hsl-cn.pak')) if common.is_dir() else []
    return next((folder for folder in folders if (folder / 'hsl-cn.pak').is_file() or (folder / 'hsl.pak').is_file()), None)


def detect_original_dir() -> tuple[Path, str, list[str]]:
    """(folder, origin, probed): HSL_ORIGINAL_DIR when set; else on Windows／Linux the Steam 經典版 GAME-PAK
    folder of any Steam library; else (and always on macOS) WINEPREFIX drive_c/hsl, whether or not it exists."""
    explicit = os.environ.get('HSL_ORIGINAL_DIR')
    if explicit:
        return Path(explicit).expanduser(), 'HSL_ORIGINAL_DIR', []
    probed: list[str] = []
    if sys.platform == 'win32' or sys.platform.startswith('linux'):
        for library in _steam_libraries(_steam_roots()):
            probed.append(str(library))
            found = _steam_game_pak(library)
            if found is not None:
                return found, f'Steam library {library}', probed
    return (WINE_PREFIX / 'drive_c/hsl').expanduser(), 'WINEPREFIX drive_c/hsl', probed


ORIGINAL_SOURCE_DIR, ORIGINAL_DIR_ORIGIN, ORIGINAL_DIR_PROBED = detect_original_dir()


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
        elif sys.platform == 'win32' and not link.is_symlink() and (link.name not in wanted or not _mirrors(link, wanted[link.name])):
            os.rmdir(link) if link.is_dir() else link.unlink()  # rmdir drops a junction, never a real non-empty folder
    for name, target in wanted.items():
        if not (view / name).is_symlink() and not (view / name).exists():
            _link(view / name, target)
    return view


def _link(link: Path, target: Path) -> None:
    """A symlink; where Windows refuses one (no admin, no developer mode): a junction for a directory, a hard
    link for a file, a copy when the file sits on another volume."""
    try:
        link.symlink_to(target, target_is_directory=target.is_dir())
        return
    except OSError:
        if sys.platform != 'win32':
            raise
    if target.is_dir():
        import _winapi
        _winapi.CreateJunction(str(target), str(link))
        return
    try:
        os.link(target, link)
    except OSError:
        shutil.copy2(target, link)


def _mirrors(entry: Path, target: Path) -> bool:
    """A Windows fallback entry still stands for target: same file (hard link, junction) or an unchanged copy."""
    try:
        if entry.samefile(target):
            return True
        a, b = entry.stat(), target.stat()
    except OSError:
        return False
    return entry.is_file() and a.st_size == b.st_size and int(a.st_mtime) == int(b.st_mtime)


_PAK = _chosen_pak(ORIGINAL_SOURCE_DIR)
ORIGINAL_ROOT = (original_view(ORIGINAL_SOURCE_DIR, _PAK) if _PAK.is_file() and _PAK != ORIGINAL_SOURCE_DIR / 'hsl.pak'
                 else ORIGINAL_SOURCE_DIR)
ORIGINAL_PAK = ORIGINAL_ROOT / 'hsl.pak'
ORIGINAL_MOVIE_PAK = ORIGINAL_ROOT / 'movie.pak'
ORIGINAL_EXE = ORIGINAL_ROOT / 'hsl01.exe'

# The user-owned Steam 經典版 folder (幻世錄 重製版 app 4030150 ships the 1998 game as GAME-PAK/):
# the only source of the original music\\NN.wav tracks and of the second data pack (hsl.pak = Steam
# default, hsl-cn.pak = the pack our ORIGINAL_PAK matches). Fetch and verify with tools/hsl_steam_classic.py.
# HSL_ORIGINAL_DIR naming a Steam folder, or a detected one (it has music/), is the default.
STEAM_CLASSIC_ROOT = Path(os.environ.get('HSL_STEAM_CLASSIC') or (
    str(ORIGINAL_SOURCE_DIR) if ORIGINAL_DIR_ORIGIN != 'WINEPREFIX drive_c/hsl' and (ORIGINAL_SOURCE_DIR / 'music').is_dir()
    else str(Path.home() / 'hsl-steam/fancy-realm/GAME-PAK'))).expanduser()
