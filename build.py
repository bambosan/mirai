#!/usr/bin/env python3
from __future__ import annotations

import argparse
import contextlib
import dataclasses
import fnmatch
import hashlib
import inspect
import io
import json
import multiprocessing
import os
import platform as py_platform
import queue
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import traceback
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

# --------------------------------------------------------------------------- #
# Layout and constants
# --------------------------------------------------------------------------- #
ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
CACHE_DIR = ROOT / ".mirai-build"

DEFAULT_PLATFORMS = ["android"]

LAZURITE_ARCHIVE = (
    "https://github.com/bambosan/lazurite-albite-compat/archive/refs/heads/main.zip"
)

ALBITE_VERSION = "v0.4.0"
ALBITE_EXE = "albite.exe" if os.name == "nt" else "albite"
ALBITE_ASSETS = {
    ("linux", "x86_64"): "albite-linux-x86_64.tar.gz",
    ("windows", "x86_64"): "albite-windows-x86_64.zip",
}
ALBITE_RELEASE_URL = (
    "https://github.com/bambosan/albite/releases/download/{tag}/{asset}"
)
ALBITE_PROFILES = {
    "ESSL_310": "310_es",
    "Metal": "msl",
    "Direct3D_SM60": "s_6_0",
    "Direct3D_SM65": "s_6_5",
}
ALBITE_STAGES = {"Vertex": "v", "Fragment": "f", "Compute": "c"}

SOURCE_SUFFIXES = {".vert", ".frag", ".comp", ".glsl"}
INCLUDE_RE = re.compile(r'^[ \t]*#[ \t]*include[ \t]*(["<])([^">]+)[">]', re.M)
LINE_DIRECTIVE_RE = re.compile(r"^\s*#\s*line\b")

MATERIAL_EXT = ".material.bin"
VANILLA_MATERIAL_EXT = ".material.json"


# --------------------------------------------------------------------------- #
# Tiny formatting helpers
# --------------------------------------------------------------------------- #
_COLOR = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None

_TAG_WIDTH = 8
_TAG_COLORS = {
    "build": "36",  # cyan
    "remove": "33",  # yellow
    "queued": "36",  # cyan
    "built": "32",  # green
    "FAILED": "1;31",  # bold red
    "removed": "33",  # yellow
}


def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _COLOR else text


def _tag(label: str) -> str:
    text = f"{label:<{_TAG_WIDTH}}"
    color = _TAG_COLORS.get(label)
    return _c(color, text) if color else text


def _row(tag: str, name: str, detail: str = "", counter: str = "") -> str:
    prefix = f"{counter} " if counter else ""
    return f"{prefix}{_tag(tag)} {name:<42}  {detail}".rstrip()


def _note(text: str) -> None:
    print(f"{_c('33', 'note:')} {text}")


def fmt_time(seconds: float) -> str:
    return f"{seconds * 1000:.0f}ms" if seconds < 1 else f"{seconds:.1f}s"


def target_slug(profiles: list[str]) -> str:
    """Stable, order-independent name used for output/cache paths ('android-vclouds')."""
    return "-".join(sorted(profiles))


def target_label(profiles: list[str]) -> str:
    """Human readable name used in messages ('android+vclouds')."""
    return "+".join(sorted(profiles))


def _hash_key(value) -> str:
    return hashlib.sha256(json.dumps(value).encode()).hexdigest()[:32]


# --------------------------------------------------------------------------- #
# Progress events
# --------------------------------------------------------------------------- #
_EMIT = None  # set by run_jobs(): callable(event_tuple) or None


def _emit(event: tuple) -> None:
    emit = _EMIT
    if emit is not None:
        try:
            emit(event)
        except Exception:
            pass  # progress must never break a build


# --------------------------------------------------------------------------- #
# Lazurite adapter
# --------------------------------------------------------------------------- #
def compile_material(
    profiles: list[str],
    material_dir: Path,
    output_dir: Path,
    albite: Path,
    max_workers: int,
) -> None:
    from lazurite.project.project import compile as lazurite_compile

    lazurite_compile(
        project_path=str(SRC),
        profiles=list(profiles),
        output_folder=str(output_dir),
        material_patterns=[str(material_dir)],
        defines=[],
        albite_path=str(albite),
        max_workers=max_workers,
    )


_ACTIVE: "ShaderCache | None" = None  # cache for the job running in this process
_TL = threading.local()
_HOOKS_INSTALLED = False


def _load_shader_hook_targets():
    try:
        import lazurite.compiler.albite as lz_albite
        import lazurite.project.project as lz_project

        orig_compile = lz_albite.AlbiteCompiler.compile
        orig_parse = lz_albite.parse_stage
        signature = inspect.signature(orig_compile)
        required = ("file", "platform", "stage", "include", "defines", "options")
        for name in required:
            if name not in signature.parameters:
                raise AttributeError(
                    f"AlbiteCompiler.compile has no '{name}' parameter"
                )
        return (
            lz_albite,
            lz_project,
            orig_compile,
            orig_parse,
            signature,
            lz_project.ThreadPoolExecutor,
        )
    except Exception:
        return None


def _make_parse_hook(orig_parse):
    def parse_hook(data, platform, stage):
        result = orig_parse(data, platform, stage)
        _TL.raw = data  # remember the raw albite output of the last successful parse
        return result

    return parse_hook


def _reuse_cached_shader(
    cache, orig_parse, blob, used, via_preprocess, platform, stage
):
    try:
        result = orig_parse(blob, platform, stage)
    except Exception:
        return None  # unreadable entry: fall through and recompile
    cache.record(used, hit=True, via_preprocess=via_preprocess)
    return result


def _try_whole_file_hit(cache, orig_parse, key, platform, stage):
    found = cache.lookup(key)
    if found is None:
        return None
    return _reuse_cached_shader(
        cache, orig_parse, found[0], found[1], False, platform, stage
    )


def _try_preprocessed_hit(cache, orig_parse, key, expanded, platform, stage):
    if expanded is None or not cache.read:
        return None
    blob = cache.read_blob(expanded)
    if blob is None:
        return None
    result = _reuse_cached_shader(
        cache, orig_parse, blob, [key, expanded], True, platform, stage
    )
    if result is not None:
        cache.alias(key, expanded)
    return result


def _compile_and_store(self, cache, orig_compile, key, expanded, args, kwargs):
    _TL.raw = None
    result = orig_compile(self, *args, **kwargs)
    raw = getattr(_TL, "raw", None)
    if raw:
        cache.store(key, expanded, raw)
    cache.record([key] if expanded is None else [key, expanded], hit=False)
    return result


def _compile_shader_with_cache(
    self, cache, orig_compile, orig_parse, signature, args, kwargs
):
    bound = signature.bind(self, *args, **kwargs)
    bound.apply_defaults()
    arguments = bound.arguments
    platform = arguments["platform"]
    stage = arguments["stage"]
    key = cache.key(
        arguments["file"],
        platform,
        stage,
        arguments["include"],
        arguments["defines"],
        arguments["options"],
    )

    result = _try_whole_file_hit(cache, orig_parse, key, platform, stage)
    if result is not None:
        return result

    expanded = cache.expanded_key(
        getattr(self, "albite_path", None),
        arguments["file"],
        platform,
        stage,
        arguments["include"],
        arguments["defines"],
        arguments["options"],
    )
    result = _try_preprocessed_hit(cache, orig_parse, key, expanded, platform, stage)
    if result is not None:
        return result
    return _compile_and_store(self, cache, orig_compile, key, expanded, args, kwargs)


def _make_compile_hook(orig_compile, orig_parse, signature):
    def compile_hook(self, *args, **kwargs):
        cache = _ACTIVE
        if cache is None:
            return orig_compile(self, *args, **kwargs)
        return _compile_shader_with_cache(
            self, cache, orig_compile, orig_parse, signature, args, kwargs
        )

    return compile_hook


def _prewarm_albite_variants(executor, cache, fn, iterables) -> None:
    try:
        if getattr(fn, "__name__", "") != "_compile_albite_shader_async":
            return
        compilers, files, stages, platforms, includes, defines, options = iterables
        albite_path = getattr(compilers[0], "albite_path", None)
        items = list(zip(files, platforms, stages, includes, defines, options))
        workers = getattr(executor, "_max_workers", None) or os.cpu_count() or 1
        cache.prewarm_preprocess(albite_path, items, workers)
    except Exception:
        return


def _make_counting_executor(base_executor):
    class CountingExecutor(base_executor):
        def map(self, fn, *iterables, **kw):
            cache = _ACTIVE
            if cache is not None and iterables:
                with contextlib.suppress(TypeError):
                    cache.set_total(len(iterables[0]))
                _prewarm_albite_variants(self, cache, fn, iterables)
            return super().map(fn, *iterables, **kw)

    return CountingExecutor


def install_shader_hooks() -> bool:
    global _HOOKS_INSTALLED
    if _HOOKS_INSTALLED:
        return True

    targets = _load_shader_hook_targets()
    if targets is None:
        return False
    lz_albite, lz_project, orig_compile, orig_parse, signature, base_executor = targets

    lz_albite.AlbiteCompiler.compile = _make_compile_hook(
        orig_compile, orig_parse, signature
    )
    lz_albite.parse_stage = _make_parse_hook(orig_parse)
    lz_project.ThreadPoolExecutor = _make_counting_executor(base_executor)
    _HOOKS_INSTALLED = True
    return True


# --------------------------------------------------------------------------- #
# Hashing and #include scanning
# --------------------------------------------------------------------------- #
def file_sha(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def rel_key(path: Path) -> str:
    try:
        return path.relative_to(SRC).as_posix()
    except ValueError:
        return os.path.relpath(path, ROOT)


class FileInfo:
    def __init__(self, search_paths: list[Path]):
        self.search_paths = search_paths
        self._hash: dict[Path, str] = {}
        self._includes: dict[Path, list[tuple[bool, str]]] = {}
        self._sig: dict[Path, list[str]] = {}

    def sha(self, path: Path) -> str:
        if path not in self._hash:
            self._hash[path] = file_sha(path)
        return self._hash[path]

    def includes(self, path: Path) -> list[tuple[bool, str]]:
        if path not in self._includes:
            text = path.read_text(errors="ignore")
            self._includes[path] = [
                (q == '"', name) for q, name in INCLUDE_RE.findall(text)
            ]
        return self._includes[path]

    def resolve(
        self, name: str, quoted: bool, including: Path, entry_dir: Path
    ) -> Path | None:
        candidates = []
        if quoted:
            candidates.append(including.parent)
        candidates.append(entry_dir)
        candidates.extend(self.search_paths)
        for base in candidates:
            p = Path(os.path.normpath(base / name))
            if p.is_file():
                return p
        return None

    def closure(self, roots: list[Path]) -> set[Path]:
        found: set[Path] = set()
        for root in roots:
            entry_dir = root.parent
            seen = {root}
            stack = [root]
            while stack:
                current = stack.pop()
                for quoted, name in self.includes(current):
                    target = self.resolve(name, quoted, current, entry_dir)
                    if target is not None and target not in seen:
                        seen.add(target)
                        found.add(target)
                        stack.append(target)
        return found

    def signature(self, root: Path) -> list[str]:
        root = Path(os.path.normpath(root))
        if root not in self._sig:
            files = {root} | self.closure([root])
            self._sig[root] = [f"{rel_key(p)}:{self.sha(p)}" for p in sorted(files)]
        return self._sig[root]


def vanilla_files(mat_dir: Path, merge_sources: list[str]) -> list[Path]:
    name = mat_dir.name
    mj = mat_dir / VANILLA_MATERIAL_EXT
    if mj.is_file():
        import pyjson5

        try:
            with open(mj) as f:
                name = None if "name" in pyjson5.load(f) else name
        except Exception:
            name = None
    paths = [Path(p) for p in merge_sources]
    if name is None:
        return paths
    wanted = {name + MATERIAL_EXT, name + VANILLA_MATERIAL_EXT}
    return [p for p in paths if p.name in wanted]


def material_inputs(
    mat_dir: Path, info: FileInfo, merge_sources: list[str]
) -> dict[str, str]:
    own = sorted(p for p in mat_dir.rglob("*") if p.is_file())
    roots = [p for p in own if p.suffix in SOURCE_SUFFIXES]
    files = (
        set(own)
        | info.closure(roots)
        | {p for p in vanilla_files(mat_dir, merge_sources) if p.is_file()}
    )
    return {rel_key(p): info.sha(p) for p in sorted(files)}


def fingerprint(files: dict[str, str]) -> str:
    return hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()


def global_state(albite: Path) -> dict[str, str]:
    import importlib.metadata as md

    return {
        "lazurite": md.version("lazurite"),
        "albite": file_sha(albite),
        "project.json": file_sha(SRC / "project.json"),
    }


# --------------------------------------------------------------------------- #
# Per-shader cache
# --------------------------------------------------------------------------- #
BATCH_MIN_PER_PROCESS = 8
_BATCH_SUPPORT: dict[str, bool] = {}


def albite_supports_batch(albite_path) -> bool:
    key = str(albite_path)
    if key not in _BATCH_SUPPORT:
        try:
            r = subprocess.run([key, "--help"], capture_output=True, timeout=30)
            _BATCH_SUPPORT[key] = b"--batch-preprocess" in (r.stdout + r.stderr)
        except (OSError, subprocess.SubprocessError):
            _BATCH_SUPPORT[key] = False
    return _BATCH_SUPPORT[key]


def _parse_batch_output(data: bytes, count: int) -> list[bytes | None]:
    out: list[bytes | None] = []
    pos = 0
    while len(out) < count:
        eol = data.find(b"\n", pos)
        if eol < 0:
            break
        head = data[pos:eol].split(b" ")
        if len(head) != 2 or head[0] not in (b"OK", b"ERR") or not head[1].isdigit():
            break
        size = int(head[1])
        body = data[eol + 1 : eol + 1 + size]
        if len(body) != size:
            break
        out.append(body if head[0] == b"OK" else None)
        pos = eol + 1 + size
    return out


def _run_preprocess_batch(
    albite_path, requests: list[list[str]], results: dict
) -> None:
    payload = "".join("\n".join(args) + "\n\n" for args in requests).encode()
    try:
        proc = subprocess.run(
            [str(albite_path), "--batch-preprocess"],
            input=payload,
            capture_output=True,
            timeout=600,
        )
    except (OSError, subprocess.SubprocessError):
        return
    for args, body in zip(requests, _parse_batch_output(proc.stdout, len(requests))):
        results[tuple(args)] = body


class ShaderCache:
    def __init__(
        self,
        directory: Path,
        albite_sha: str,
        search_paths: list[Path],
        read: bool,
        material: str,
        can_preprocess: bool,
    ):
        self.dir = directory
        self.albite_sha = albite_sha
        self.search_paths = search_paths
        self.read = read
        self.material = material
        self.can_preprocess = can_preprocess
        self.info = FileInfo(search_paths)
        self.pre_memo: dict[tuple, bytes | None] = {}
        self.keys: list[str] = []
        self.compiled = 0
        self.hits = 0
        self.pp_hits = 0
        self._lock = threading.Lock()

    def key(self, file, platform, stage, include, defines, options) -> str:
        return _hash_key(
            [
                self.albite_sha,
                platform.name,
                stage.name,
                [rel_key(Path(os.path.normpath(i))) for i in (include or [])],
                [d.format_bgfx() for d in (defines or [])],
                list(options or []),
                self.info.signature(Path(file)),
            ]
        )

    def _preprocess_args(
        self, file, platform, stage, include, defines, options
    ) -> list[str] | None:
        profile = ALBITE_PROFILES.get(platform.name)
        stage_type = ALBITE_STAGES.get(stage.name)
        if profile is None or stage_type is None:
            return None
        args = ["-E", "-f", str(file), "-t", stage_type, "-p", profile]
        for item in include or []:
            args.extend(("-i", item))
        if defines:
            args.extend(("--define", ";".join(d.format_bgfx() for d in defines)))
        if options:
            args.extend(options)
        return args

    def _expanded_hash(self, stdout: bytes, platform, stage, options) -> str:
        lines = [
            ln.rstrip()
            for ln in stdout.decode(errors="replace").splitlines()
            if ln.strip() and not LINE_DIRECTIVE_RE.match(ln)
        ]
        return _hash_key(
            [
                self.albite_sha,
                platform.name,
                stage.name,
                list(options or []),
                "\n".join(lines),
            ]
        )

    def expanded_key(
        self, albite_path, file, platform, stage, include, defines, options
    ) -> str | None:
        if not self.can_preprocess or not albite_path:
            return None
        args = self._preprocess_args(file, platform, stage, include, defines, options)
        if args is None:
            return None
        memo_key = tuple(args)
        if memo_key in self.pre_memo:  # computed in bulk by prewarm_preprocess()
            stdout = self.pre_memo.pop(memo_key)
            if stdout is None:
                return None  # let the real compile report the error properly
            return self._expanded_hash(stdout, platform, stage, options)
        try:
            proc = subprocess.run(
                [str(albite_path), *args], capture_output=True, timeout=300
            )
        except (OSError, subprocess.SubprocessError):
            return None
        if proc.returncode != 0:
            return None  # let the real compile report the error properly
        return self._expanded_hash(proc.stdout, platform, stage, options)

    def prewarm_preprocess(self, albite_path, items, workers: int) -> None:
        if not (self.can_preprocess and albite_path):
            return
        if not albite_supports_batch(albite_path):
            return
        todo: list[list[str]] = []
        seen: set[tuple] = set()
        for file, platform, stage, include, defines, options in items:
            key = self.key(file, platform, stage, include, defines, options)
            if self.read and self.lookup(key) is not None:
                continue  # whole-file hit: needs no preprocessing at all
            args = self._preprocess_args(
                file, platform, stage, include, defines, options
            )
            if args is None or any("\n" in a or not a for a in args):
                continue  # not expressible in the line protocol
            if tuple(args) not in seen:
                seen.add(tuple(args))
                todo.append(args)
        if len(todo) < 2:
            return  # nothing to amortise

        procs = max(1, min(workers, len(todo) // BATCH_MIN_PER_PROCESS))
        chunks = [todo[i::procs] for i in range(procs)]
        results: list[dict] = [{} for _ in chunks]
        threads = [
            threading.Thread(
                target=_run_preprocess_batch,
                args=(albite_path, chunk, results[i]),
                daemon=True,
            )
            for i, chunk in enumerate(chunks)
        ]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        for r in results:
            self.pre_memo.update(r)

    def _path(self, key: str, suffix: str = ".bin") -> Path:
        return self.dir / key[:2] / (key + suffix)

    def read_blob(self, key: str) -> bytes | None:
        try:
            return self._path(key).read_bytes()
        except OSError:
            return None

    def lookup(self, key: str):
        if not self.read:
            return None
        try:
            expanded = self._path(key, ".alias").read_text().strip()
        except OSError:
            expanded = ""
        if expanded:
            blob = self.read_blob(expanded)
            return (blob, [key, expanded]) if blob is not None else None
        blob = self.read_blob(key)  # stored directly (preprocess level unavailable)
        return (blob, [key]) if blob is not None else None

    def _write(self, path: Path, data: bytes) -> None:
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            fd, tmp = tempfile.mkstemp(dir=path.parent, suffix=".tmp")
            with os.fdopen(fd, "wb") as f:
                f.write(data)
            os.replace(tmp, path)
        except OSError:
            pass  # a cache that cannot be written is merely slower

    def alias(self, key: str, expanded: str) -> None:
        self._write(self._path(key, ".alias"), expanded.encode())

    def store(self, key: str, expanded: str | None, raw: bytes) -> None:
        if expanded is None:
            self._write(self._path(key), raw)
        else:
            self._write(self._path(expanded), raw)
            self.alias(key, expanded)

    def record(self, keys: list[str], hit: bool, via_preprocess: bool = False) -> None:
        with self._lock:
            self.keys.extend(keys)
            if hit:
                self.hits += 1
                if via_preprocess:
                    self.pp_hits += 1
            else:
                self.compiled += 1
        _emit(("shader", self.material, hit))

    def set_total(self, n: int) -> None:
        _emit(("total", self.material, n))


def gc_shader_cache(platform: str, cache: dict) -> int:
    root = CACHE_DIR / "shaders" / platform
    if not root.is_dir():
        return 0
    live = {k for keys in cache.get("shader_refs", {}).values() for k in keys}
    removed = 0
    now = time.time()
    for f in root.rglob("*"):
        if f.suffix in (".bin", ".alias") and f.stem not in live:
            f.unlink(missing_ok=True)
            removed += 1
        elif f.suffix == ".tmp" and now - f.stat().st_mtime > 3600:
            f.unlink(missing_ok=True)
    for d in sorted((p for p in root.glob("*") if p.is_dir()), reverse=True):
        with contextlib.suppress(OSError):
            d.rmdir()  # only succeeds when empty
    return removed


# --------------------------------------------------------------------------- #
# Build-state cache (per platform)
# --------------------------------------------------------------------------- #
def load_cache(platform: str) -> dict:
    try:
        with open(CACHE_DIR / f"{platform}.json") as f:
            data = json.load(f)
        if isinstance(data, dict) and isinstance(data.get("materials"), dict):
            data.setdefault("shader_refs", {})
            data.setdefault("timings", {})  # material -> estimated full build seconds
            return data
    except (OSError, ValueError):
        pass
    return {"global": {}, "materials": {}, "shader_refs": {}, "timings": {}}


def save_cache(platform: str, cache: dict) -> None:
    CACHE_DIR.mkdir(exist_ok=True)
    target = CACHE_DIR / f"{platform}.json"
    tmp = target.with_suffix(".json.tmp")
    with open(tmp, "w") as f:
        json.dump(cache, f, sort_keys=True, separators=(",", ":"))
    os.replace(tmp, target)


# --------------------------------------------------------------------------- #
# Planning
# --------------------------------------------------------------------------- #
def discover_materials(cfg) -> list[Path]:
    found: set[Path] = set()
    for pattern in cfg.include_patterns:
        for path in SRC.glob(pattern):
            if path.is_dir() and not any(path.match(p) for p in cfg.exclude_patterns):
                found.add(path)
    return sorted(found)


def describe_change(old: dict[str, str], new: dict[str, str]) -> str:
    changed = sorted(k for k in set(old) | set(new) if old.get(k) != new.get(k))
    shown = ", ".join(changed[:3])
    more = f" (+{len(changed) - 3} more)" if len(changed) > 3 else ""
    return f"changed: {shown}{more}"


def decide(files, entry, out_file, force, global_note) -> str | None:
    if force:
        return "forced"
    if global_note:
        return global_note
    if entry is None:
        return "not built yet (or last build failed)"
    if not out_file.is_file():
        return "output file missing"
    if entry.get("fp") != fingerprint(files):
        return describe_change(entry.get("files", {}), files)
    return None


def _select_materials(all_materials: list[Path], patterns) -> tuple[list[Path], bool]:
    if not patterns:
        return all_materials, False
    selected = [
        material
        for material in all_materials
        if any(fnmatch.fnmatchcase(material.name, pattern) for pattern in patterns)
    ]
    return selected, len(selected) != len(all_materials)


def _update_global_cache(cache: dict, glob_state: dict[str, str]) -> str | None:
    old_global = cache.get("global", {})
    global_note = None
    if old_global and old_global != glob_state:
        changed = sorted(
            key
            for key in set(old_global) | set(glob_state)
            if old_global.get(key) != glob_state.get(key)
        )
        global_note = "toolchain/project config changed: " + ", ".join(changed)
        cache["materials"] = {}
    cache["global"] = glob_state
    return global_note


def _collect_build_todo(selected, out_dir, cache, info, cfg, args, global_note):
    todo: list[tuple[Path, dict, str]] = []
    for mat_dir in selected:
        files = material_inputs(mat_dir, info, cfg.merge_source)
        out_file = out_dir / (mat_dir.name + MATERIAL_EXT)
        entry = cache["materials"].get(mat_dir.name)
        reason = decide(files, entry, out_file, args.force, global_note)
        if reason:
            todo.append((mat_dir, files, reason))
    return todo


def _find_orphans(partial, cache, all_materials) -> list[str]:
    if partial:
        return []
    material_names = {material.name for material in all_materials}
    return sorted(set(cache["materials"]) - material_names)


def _order_by_cost(todo, cache):
    timings = cache.get("timings", {})
    return sorted(todo, key=lambda item: -timings.get(item[0].name, float("inf")))


def _print_build_plan(platform, selected, todo) -> None:
    up_to_date = len(selected) - len(todo)
    bits = []
    if todo:
        bits.append(_c("33", f"{len(todo)} to build"))
    if up_to_date:
        bits.append(f"{up_to_date} up to date")
    if not bits:
        bits.append("nothing to build")
    print(_c("1;36", f"[{platform}]") + f"  {len(selected)} materials")
    print(" · ".join(bits))


def _print_dry_run(todo, orphans) -> None:
    if not todo and not orphans:
        return
    print(_c("36", "dry run") + " — no changes will be made")
    for mat_dir, _, reason in todo:
        print(_row("build", mat_dir.name, reason))
    for name in orphans:
        print(_row("remove", name + MATERIAL_EXT, "(material deleted from project)"))


def _remove_orphans(out_dir, cache, orphans) -> None:
    for name in orphans:
        (out_dir / (name + MATERIAL_EXT)).unlink(missing_ok=True)
        cache["materials"].pop(name, None)
        cache["shader_refs"].pop(name, None)
        cache["timings"].pop(name, None)
        print(_row("removed", name + MATERIAL_EXT, "(material deleted from project)"))


def _prepare_cache_for_build(platform, cache, todo) -> None:
    for mat_dir, _, _ in todo:
        cache["materials"].pop(mat_dir.name, None)
    save_cache(platform, cache)


def _finish_empty_build(platform, started, orphans, cache) -> int:
    if orphans:
        gc_shader_cache(platform, cache)
        save_cache(platform, cache)
    elapsed = f"({fmt_time(time.perf_counter() - started)})"
    print(_c("32", "nothing to do") + " " + elapsed)
    return 0


def _make_jobs(
    profiles, todo, out_dir, albite, glob_state, cfg, args, can_preprocess
):
    slug = target_slug(profiles)
    return [
        Job(
            name=mat_dir.name,
            platform=slug,
            profiles=list(profiles),
            mat_dir=str(mat_dir),
            out_dir=str(out_dir),
            albite=str(albite),
            albite_sha=glob_state["albite"],
            search_paths=[str(path) for path in cfg.include_search_paths],
            shader_dir=str(CACHE_DIR / "shaders" / slug),
            read_cache=not args.force,
            can_preprocess=can_preprocess,
        )
        for mat_dir, _, _ in todo
    ]


def _print_queued_jobs(todo, verbose) -> None:
    if not verbose:
        return
    for mat_dir, _, reason in todo:
        print(_row("queued", mat_dir.name, reason))


# --------------------------------------------------------------------------- #
# progress display
# --------------------------------------------------------------------------- #
class Reporter:
    def __init__(self, total_materials: int):
        self.tty = sys.stdout.isatty()
        self.total = total_materials
        self.finished = 0
        self.active: dict[str, dict] = {}
        self.running = False
        self._lock = threading.RLock()
        self._drawn = False
        self._last_draw = 0.0
        self._last_plain = 0.0

    # events from workers
    def handle(self, event: tuple) -> None:
        kind, name = event[0], event[1]
        with self._lock:
            if kind == "start":
                self.active[name] = {"total": None, "done": 0, "t": time.monotonic()}
                return
            st = self.active.get(name)
            if st is None:
                return  # material already finished; late event
            if kind == "total":
                st["total"] = event[2]
            elif kind == "shader":
                st["done"] += 1

    def finish(self, name: str) -> None:
        with self._lock:
            self.active.pop(name, None)
            self.finished += 1

    # drawing
    def _status(self) -> str:
        parts = []
        for name, st in sorted(self.active.items(), key=lambda kv: kv[1]["t"]):
            progress = f"{st['done']}/{st['total']}" if st["total"] else str(st["done"])
            parts.append(f"{name} {progress}")
        head = f"[{self.finished}/{self.total}] building"
        return head + (": " + " · ".join(parts) if parts else "")

    def _clear(self) -> None:
        if self._drawn:
            sys.stdout.write("\r\033[K")
            self._drawn = False

    def _draw(self) -> None:
        if not (self.tty and self.running):
            return
        width = shutil.get_terminal_size((100, 20)).columns
        text = self._status()
        if len(text) > width - 1:
            text = text[: width - 4] + "..."
        sys.stdout.write("\r\033[K" + text)
        sys.stdout.flush()
        self._drawn = True
        self._last_draw = time.monotonic()

    def print(self, line: str = "") -> None:
        with self._lock:
            self._clear()
            print(line)
            sys.stdout.flush()
            self._draw()

    def tick(self) -> None:
        with self._lock:
            if not self.running:
                return
            now = time.monotonic()
            if self.tty:
                if now - self._last_draw >= 0.1:
                    self._draw()
            elif now - self._last_plain >= 5:  # piped output: occasional plain line
                self._last_plain = now
                print(self._status())
                sys.stdout.flush()

    def start(self) -> None:
        with self._lock:
            self.running = True
            self._last_plain = time.monotonic()
            self._draw()

    def stop(self) -> None:
        with self._lock:
            self.running = False
            self._clear()
            sys.stdout.flush()


# --------------------------------------------------------------------------- #
# Building
# --------------------------------------------------------------------------- #
@dataclasses.dataclass
class Job:
    name: str
    platform: str  # target slug (used for scratch/cache names)
    mat_dir: str
    out_dir: str
    albite: str
    albite_sha: str
    search_paths: list
    shader_dir: str
    read_cache: bool
    can_preprocess: bool = False
    inner_workers: int = 1
    profiles: list = dataclasses.field(default_factory=list)


def _build_one(job: Job) -> dict:
    global _ACTIVE
    start = time.perf_counter()
    log = io.StringIO()
    tmp_root = CACHE_DIR / "tmp"
    tmp_root.mkdir(parents=True, exist_ok=True)
    tmp = Path(tempfile.mkdtemp(prefix=f"{job.platform}-{job.name}-", dir=tmp_root))

    cache = ShaderCache(
        Path(job.shader_dir),
        job.albite_sha,
        [Path(p) for p in job.search_paths],
        job.read_cache,
        job.name,
        job.can_preprocess,
    )
    hooks_ok = install_shader_hooks()
    _ACTIVE = cache if hooks_ok else None

    def stats() -> dict:
        return {
            "compiled": cache.compiled,
            "hits": cache.hits,
            "pp_hits": cache.pp_hits,
            "keys": list(cache.keys),
            "hooks": hooks_ok,
            "secs": time.perf_counter() - start,
        }

    _emit(("start", job.name))
    try:
        # build into a scratch folder, then move into place, so a failed or
        # interrupted build never leaves a half-written .material.bin behind.
        with contextlib.redirect_stdout(log), contextlib.redirect_stderr(log):
            compile_material(
                job.profiles or [job.platform],
                Path(job.mat_dir),
                tmp,
                Path(job.albite),
                job.inner_workers,
            )
        produced = tmp / (job.name + MATERIAL_EXT)
        if not produced.is_file():
            raise RuntimeError(f"Lazurite did not produce {produced.name}")
        out_dir = Path(job.out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        os.replace(produced, out_dir / produced.name)
        return {"name": job.name, "ok": True, "log": log.getvalue(), **stats()}
    except Exception as e:  # noqa: BLE001 - report every failure back to the parent
        return {
            "name": job.name,
            "ok": False,
            "log": log.getvalue(),
            "error": str(e) or e.__class__.__name__,
            "tb": traceback.format_exc(),
            **stats(),
        }
    finally:
        _ACTIVE = None
        shutil.rmtree(tmp, ignore_errors=True)


def _die_with_parent() -> None:
    try:
        import ctypes

        ctypes.CDLL(None).prctl(1, signal.SIGKILL, 0, 0, 0)  # PR_SET_PDEATHSIG
    except Exception:
        pass


def _worker_main(job: Job, events, results) -> None:
    global _EMIT
    # never touch the parent's stdout object (it may be locked by the progress thread
    # at the moment of fork); everything lazurite prints is captured by _build_one.
    sys.stdout = open(os.devnull, "w")
    if os.name == "posix":
        with contextlib.suppress(OSError):
            os.setsid()  # own process group, so the parent can kill worker + albite together
        _die_with_parent()
    signal.signal(signal.SIGINT, signal.SIG_IGN)  # the parent decides when we stop
    _EMIT = events.put
    results.put(_build_one(job))


def kill_tree(proc) -> None:
    """Kill a worker and everything it started (albite processes included)."""
    if proc.pid is not None:
        if os.name == "posix":
            with contextlib.suppress(OSError):
                os.killpg(proc.pid, signal.SIGKILL)  # the worker leads its own group
        else:
            subprocess.run(
                ["taskkill", "/F", "/T", "/PID", str(proc.pid)], capture_output=True
            )
    with contextlib.suppress(Exception):
        proc.kill()


def _lost_worker(name: str, exit_code) -> dict:
    return {
        "name": name,
        "ok": False,
        "log": "",
        "keys": [],
        "compiled": 0,
        "hits": 0,
        "pp_hits": 0,
        "hooks": True,
        "secs": 0.0,
        "tb": "",
        "error": f"worker process exited unexpectedly (exit code {exit_code})",
    }


def run_jobs(
    jobs_list: list[Job], parallel: int | None, reporter: Reporter, on_result
) -> None:
    cpu = os.cpu_count() or 2
    outer = max(1, min(parallel or cpu, len(jobs_list)))
    # few materials: let each use many threads; many materials: run them side by side.
    inner = max(1, cpu // outer)
    jobs_list = [dataclasses.replace(j, inner_workers=inner) for j in jobs_list]

    ctx = multiprocessing.get_context("fork" if os.name == "posix" else "spawn")
    if ctx.get_start_method() == "fork":
        install_shader_hooks()
    events, results = ctx.Queue(), ctx.Queue()
    stop = threading.Event()

    def ui_loop() -> None:
        while not stop.is_set():
            try:
                reporter.handle(events.get(timeout=0.1))
                while True:
                    reporter.handle(events.get_nowait())
            except queue.Empty:
                pass
            reporter.tick()

    ui = threading.Thread(target=ui_loop, daemon=True)
    pending = list(jobs_list)
    running: dict[str, "multiprocessing.process.BaseProcess"] = {}
    exited_at: dict[str, float] = {}

    reporter.start()
    ui.start()
    try:
        while pending or running:
            while pending and len(running) < outer:
                job = pending.pop(0)
                proc = ctx.Process(
                    target=_worker_main, args=(job, events, results), daemon=True
                )
                proc.start()
                running[job.name] = proc
            try:
                res = results.get(timeout=0.2)
            except queue.Empty:
                # a worker that died without reporting
                now = time.monotonic()
                for name, proc in list(running.items()):
                    if (
                        not proc.is_alive()
                        and now - exited_at.setdefault(name, now) > 2.0
                    ):
                        del running[name]
                        on_result(_lost_worker(name, proc.exitcode))
                continue
            proc = running.pop(res["name"], None)
            if proc is not None:
                proc.join(timeout=5)
            on_result(res)
    finally:
        # normal completion leaves nothing running; on Ctrl-C or an error this kills
        # every worker and the albite processes below it
        for proc in running.values():
            kill_tree(proc)
        for proc in running.values():
            proc.join(timeout=2)
        stop.set()
        ui.join(timeout=1)
        reporter.stop()


# --------------------------------------------------------------------------- #
# Result handling
# --------------------------------------------------------------------------- #
class _BuildResultHandler:
    SAVE_INTERVAL = 2.0

    def __init__(self, platform, args, todo, reporter, cache):
        self.platform = platform
        self.args = args
        self.todo_count = len(todo)
        self.reporter = reporter
        self.cache = cache
        self.by_name = {
            material.name: (files, reason) for material, files, reason in todo
        }
        self.failures: list[dict] = []
        self.totals = {"compiled": 0, "hits": 0, "pp_hits": 0}
        self.hooks_missing = False
        self._dirty = False
        self._last_save = 0.0

    def _save(self) -> None:
        self._dirty = True
        now = time.monotonic()
        if now - self._last_save >= self.SAVE_INTERVAL:
            self.flush()

    def flush(self) -> None:
        if self._dirty:
            save_cache(self.platform, self.cache)
            self._dirty = False
            self._last_save = time.monotonic()

    def _note_timing(self, name: str, res: dict) -> None:
        if res["compiled"] <= 0:
            return  # all cache hits: says nothing about the real compile cost
        timings = self.cache.setdefault("timings", {})
        old = timings.get(name)
        # keep the larger value, decaying slowly, so a mostly-cached run does not
        # make an expensive material look cheap
        timings[name] = round(
            res["secs"] if old is None else max(res["secs"], old * 0.8), 2
        )

    def __call__(self, res: dict) -> None:
        name = res["name"]
        self.reporter.finish(name)
        tag = f"[{self.reporter.finished}/{self.todo_count}]"

        self.totals["compiled"] += res["compiled"]
        self.totals["hits"] += res["hits"]
        self.totals["pp_hits"] += res["pp_hits"]
        self.hooks_missing = self.hooks_missing or not res["hooks"]
        # keep shader keys even on failure, so a retry resumes quickly.
        self.cache["shader_refs"][name] = res["keys"]

        detail = (
            f"{res['compiled']} compiled, {res['hits']} cached" if res["hooks"] else ""
        )
        if res["ok"]:
            self._record_success(name, tag, detail, res)
        else:
            self._record_failure(name, tag, detail, res)
        self._save()

    def _record_success(self, name: str, tag: str, detail: str, res: dict) -> None:
        files, _ = self.by_name[name]
        self.cache["materials"][name] = {"fp": fingerprint(files), "files": files}
        self._note_timing(name, res)
        self.reporter.print(_row("built", name, detail, counter=tag))
        if not self.args.verbose:
            return
        extra = [
            line
            for line in res["log"].strip().splitlines()
            if line.strip() and line.strip() != name
        ]
        if extra:
            self.reporter.print("\n".join(extra))

    def _record_failure(self, name: str, tag: str, detail: str, res: dict) -> None:
        self.failures.append(res)
        self.reporter.print(_row("FAILED", name, detail, counter=tag))


def _print_failure_details(failures, platform, verbose) -> None:
    for res in failures:
        print()
        print(_c("1;31", f"── {res['name']} ({platform}) failed ──"))
        for line in (res["error"] or "").splitlines() or [""]:
            print(line)
        if verbose and res.get("tb"):
            print(res["tb"].rstrip())


def _print_build_summary(
    platform, selected_count, todo_count, started, handler, removed, verbose
) -> None:
    if handler.hooks_missing:
        _note(
            "this Lazurite version has no per-shader cache support; "
            "only whole materials are cached."
        )
    _print_failure_details(handler.failures, platform, verbose)

    elapsed = fmt_time(time.perf_counter() - started)
    built = todo_count - len(handler.failures)
    failed = len(handler.failures)
    up_to_date = selected_count - todo_count

    bits = []
    if built:
        bits.append(_c("32", f"{built} built"))
    if up_to_date:
        bits.append(f"{up_to_date} up to date")
    if failed:
        bits.append(_c("31", f"{failed} failed"))
    if not bits:
        bits.append("nothing to do")
    print()
    print(" · ".join(bits) + f"   {elapsed}")

    totals = handler.totals
    if not handler.hooks_missing and (totals["compiled"] or totals["hits"]):
        line = f"{totals['compiled']} shaders compiled, {totals['hits']} reused"
        if verbose and removed:
            line += f", {removed} cache entries pruned"
        print(line)

    if failed:
        names = ", ".join(r["name"] for r in handler.failures)
        print(_c("1;31", "failed: ") + names)


# --------------------------------------------------------------------------- #
# Per-platform build driver
# --------------------------------------------------------------------------- #
def build_target(
    profiles: list[str],
    args,
    glob_state: dict[str, str],
    albite: Path,
    can_preprocess: bool = False,
) -> int:
    from lazurite.project.project_config import ProjectConfig

    started = time.perf_counter()
    label = target_label(profiles)
    slug = target_slug(profiles)
    cfg = ProjectConfig()
    cfg.read_json_file(str(SRC / "project.json"), list(profiles))

    all_materials = discover_materials(cfg)
    selected, partial = _select_materials(all_materials, args.material)
    if args.material and not selected:
        print(f"{_c('33', 'note:')} {label}: no material matches {args.material}")
        return 1

    out_dir = ROOT / f"output-{slug}"
    cache = load_cache(slug)
    global_note = _update_global_cache(cache, glob_state)
    info = FileInfo([Path(path) for path in cfg.include_search_paths])
    todo = _collect_build_todo(selected, out_dir, cache, info, cfg, args, global_note)
    orphans = _find_orphans(partial, cache, all_materials)
    _print_build_plan(label, selected, todo)

    if args.dry_run:
        _print_dry_run(todo, orphans)
        return 0

    _remove_orphans(out_dir, cache, orphans)
    _prepare_cache_for_build(slug, cache, todo)
    if not todo:
        return _finish_empty_build(slug, started, orphans, cache)

    todo = _order_by_cost(todo, cache)
    reporter = Reporter(len(todo))
    handler = _BuildResultHandler(slug, args, todo, reporter, cache)
    jobs_list = _make_jobs(
        profiles, todo, out_dir, albite, glob_state, cfg, args, can_preprocess
    )
    _print_queued_jobs(todo, args.verbose)
    try:
        run_jobs(jobs_list, args.jobs, reporter, handler)
    finally:
        handler.flush()  # persist finished materials even on Ctrl-C or an error

    removed = gc_shader_cache(slug, cache)
    save_cache(slug, cache)
    _print_build_summary(
        label, len(selected), len(todo), started, handler, removed, args.verbose
    )
    return 1 if handler.failures else 0


# --------------------------------------------------------------------------- #
# Setup: install Lazurite and albite automatically when they are missing
# --------------------------------------------------------------------------- #
class SetupError(Exception):
    pass


def _run_streaming(cmd: list[str]) -> tuple[int, str]:
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
    )
    tail: list[str] = []
    assert proc.stdout is not None
    for line in proc.stdout:
        print(line.rstrip())
        tail = (tail + [line])[-40:]
    return proc.wait(), "".join(tail)


def lazurite_state() -> str:
    import importlib.util

    try:
        if importlib.util.find_spec("lazurite") is None:
            return "missing"
    except (ImportError, ValueError):
        return "missing"
    try:
        return (
            "ok"
            if importlib.util.find_spec("lazurite.compiler.albite")
            else "no-albite"
        )
    except (ImportError, ValueError):
        return "no-albite"


def ensure_lazurite(allow_install: bool) -> None:
    state = lazurite_state()
    if state == "ok":
        return
    what = (
        "Lazurite is not installed in this Python environment"
        if state == "missing"
        else "the installed Lazurite has no albite support (it is not the lazurite-albite-compat fork)"
    )
    manual = f"{sys.executable} -m pip install {LAZURITE_ARCHIVE}"
    if not allow_install:
        raise SetupError(
            f"{what}.\nRun ./build.py without --dry-run/--no-install to install it, or:\n"
            f"  {manual}"
        )

    print()
    print(_c("33", "setup:") + f" {what}.")
    print("Installing lazurite-albite-compat with pip ...")
    cmd = [sys.executable, "-m", "pip", "install", "--disable-pip-version-check"]
    if state == "no-albite":
        cmd.append("--force-reinstall")
    code, tail = _run_streaming(cmd + [LAZURITE_ARCHIVE])
    if code != 0:
        hint = ""
        if "externally-managed" in tail:
            hint = (
                "\nThis Python is system-managed; activate your virtualenv first "
                "(or create one: python3 -m venv .venv)."
            )
        raise SetupError(
            f"pip failed (exit code {code}).{hint}\nManual command: {manual}"
        )
    print(_c("32", "Lazurite installed") + ", restarting the build ...\n")
    sys.stdout.flush()
    argv = [sys.executable, str(Path(__file__).resolve()), *sys.argv[1:]]
    env = dict(os.environ, MIRAI_BOOTSTRAPPED="1")
    if os.name == "nt":
        raise SystemExit(subprocess.call(argv, env=env))
    os.execve(sys.executable, argv, env)


def _host_asset() -> str | None:
    os_name = (
        "windows"
        if os.name == "nt"
        else ("linux" if sys.platform.startswith("linux") else sys.platform)
    )
    arch = py_platform.machine().lower()
    arch = "x86_64" if arch in ("x86_64", "amd64") else arch
    return ALBITE_ASSETS.get((os_name, arch))


def _download(url: str, target: Path, label: str) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": "mirai-build"})
    tty = sys.stdout.isatty()
    with urllib.request.urlopen(req, timeout=60) as resp, open(target, "wb") as out:
        total = int(resp.headers.get("Content-Length") or 0)
        got, shown = 0, -1
        while True:
            chunk = resp.read(1 << 18)
            if not chunk:
                break
            out.write(chunk)
            got += len(chunk)
            if total:
                pct = got * 100 // total
                if (tty and pct != shown) or (not tty and pct // 25 != shown // 25):
                    shown = pct
                    end = "\r" if tty else "\n"
                    print(
                        f"{label}: {pct:3d}%  ({got / 1e6:.1f}/{total / 1e6:.1f} MB)",
                        end=end,
                        flush=True,
                    )
    if tty:
        print()
    if total and got != total:
        raise OSError(f"incomplete download ({got} of {total} bytes)")


def _extract(archive: Path, into: Path) -> None:
    def check(name: str) -> None:
        parts = Path(name).parts
        if Path(name).is_absolute() or ".." in parts:
            raise SetupError(f"refusing unsafe path in archive: {name}")

    if archive.name.endswith(".zip"):
        with zipfile.ZipFile(archive) as zf:
            for n in zf.namelist():
                check(n)
            zf.extractall(into)
    else:
        with tarfile.open(archive) as tf:
            members = []
            for m in tf.getmembers():
                check(m.name)
                if m.isfile() or m.isdir():  # no links/devices
                    members.append(m)
            kw = {"filter": "data"} if hasattr(tarfile, "data_filter") else {}
            tf.extractall(into, members=members, **kw)


def download_albite() -> Path:
    asset = _host_asset()
    if asset is None:
        raise SetupError(
            f"no prebuilt albite for {sys.platform}/{py_platform.machine()}. Build it from source"
        )
    dest = ROOT / "albite"
    if dest.exists():
        if dest.is_dir() and not any(dest.iterdir()):
            dest.rmdir()
        else:
            raise SetupError(
                f"{dest} exists but contains no albite executable. Move it away, "
                f"or pass --albite PATH."
            )
    url = ALBITE_RELEASE_URL.format(tag=ALBITE_VERSION, asset=asset)
    print()
    print(
        _c("33", "setup:")
        + f" albite not found, downloading {asset} ({ALBITE_VERSION}) ..."
    )
    CACHE_DIR.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="albite-download-", dir=CACHE_DIR))
    try:
        archive = work / asset
        try:
            _download(url, archive, asset)
        except (urllib.error.URLError, OSError) as e:
            raise SetupError(
                f"download failed: {e}\nGet it manually from {url}\n"
                f"and extract it so that {dest / ALBITE_EXE} exists."
            ) from e
        unpacked = work / "unpacked"
        unpacked.mkdir()
        _extract(archive, unpacked)
        found = sorted(
            (p for p in unpacked.rglob(ALBITE_EXE) if p.is_file()),
            key=lambda p: len(p.parts),
        )
        if not found:
            raise SetupError(f"{asset} does not contain {ALBITE_EXE}")
        os.replace(found[0].parent, dest)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    exe = dest / ALBITE_EXE
    if os.name == "posix":
        exe.chmod(exe.stat().st_mode | 0o111)
    try:
        ok = (
            subprocess.run([str(exe), "-v"], capture_output=True, timeout=30).returncode
            == 0
        )
    except (OSError, subprocess.SubprocessError) as e:
        print(f"Albite could not be launched: {e}", file=sys.stderr)
        ok = False
    if not ok:
        shutil.rmtree(dest, ignore_errors=True)
        raise SetupError(
            "the downloaded albite failed its startup check, see the output above."
        )
    print(_c("32", f"albite {ALBITE_VERSION} installed") + f" to {dest}{os.sep}\n")
    return exe


def locate_albite() -> Path | None:
    folder_exe = ROOT / "albite" / ALBITE_EXE
    if folder_exe.is_file():
        return folder_exe
    return None


def ensure_albite(explicit: str | None, allow_install: bool) -> Path:
    if explicit:  # an explicit path is never replaced by a download
        path = Path(explicit).resolve()
        if not path.is_file():
            raise SetupError(f"albite executable not found at {path}")
        return path
    found = locate_albite()
    if found is not None:
        return found
    if not allow_install:
        raise SetupError(
            f"albite is not installed (expected {ROOT / 'albite' / ALBITE_EXE}).\n"
            f"Run ./build.py without --dry-run/--no-install to download it, "
            f"or pass --albite PATH."
        )
    return download_albite()


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #
def albite_supports_preprocess(albite: Path) -> bool:
    try:
        r = subprocess.run([str(albite), "--help"], capture_output=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return False
    return b"--preprocess-only" in (r.stdout + r.stderr)


def available_profiles() -> dict[str, dict]:
    import pyjson5

    with open(SRC / "project.json") as f:
        return dict(pyjson5.load(f).get("profiles", {}))


def _resolve_targets(
    platforms: list[str], extras: list[str], profiles: dict[str, dict]
) -> list[list[str]] | None:
    """One build per platform; every -p profile is merged into each of them."""
    for name in [*platforms, *extras]:
        if name != "all" and name not in profiles:
            print(
                f"error: unknown profile '{name}'. Available: "
                f"{', '.join(profiles)}, all"
            )
            return None

    targets: list[str] = []
    for name in platforms:
        if name == "all":
            with_platforms = [n for n, body in profiles.items() if "platforms" in body]
            candidates = with_platforms or list(profiles)
        else:
            candidates = [name]
        for t in candidates:
            if t not in targets:
                targets.append(t)
    return [[t, *(e for e in extras if e != t)] for t in targets]


def parse_args(argv):
    p = argparse.ArgumentParser(
        prog="build.py",
        epilog="example: build.py android -p vclouds -m DeferredWater",
    )
    p.add_argument(
        "platforms",
        nargs="*",
        metavar="PLATFORM",
        help=f"platform profiles from src/project.json, or 'all' (default: {' '.join(DEFAULT_PLATFORMS)})",
    )
    p.add_argument(
        "-p",
        "--profile",
        nargs="+",
        default=[],
        metavar="NAME",
        help="extra profiles merged into every build (macros, etc.), e.g. vclouds",
    )
    p.add_argument(
        "-m",
        "--material",
        nargs="+",
        metavar="NAME",
        help="only consider these materials (names or globs, e.g. 'Actor*')",
    )
    p.add_argument(
        "-f",
        "--force",
        action="store_true",
        help="rebuild everything from scratch, ignoring both caches",
    )
    p.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help="show what would be rebuilt, change nothing",
    )
    p.add_argument(
        "-j",
        "--jobs",
        type=int,
        metavar="N",
        help="materials to compile in parallel (default: CPU count)",
    )
    p.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="show reasons, compiler warnings and tracebacks",
    )
    p.add_argument(
        "--albite",
        metavar="PATH",
        help="albite executable (default: ./albite/albite, downloaded if missing)",
    )
    p.add_argument(
        "--no-install",
        action="store_true",
        help="never download albite or pip-install Lazurite; fail with instructions instead",
    )
    return p.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    os.chdir(ROOT)  # lazurite prints/uses relative paths; keep them predictable

    if not (SRC / "project.json").is_file():
        print(f"error: {SRC / 'project.json'} not found")
        return 2

    allow_install = not (args.no_install or args.dry_run)
    try:
        ensure_lazurite(allow_install)
        albite = ensure_albite(args.albite, allow_install)
    except SetupError as e:
        print(f"error: {e}")
        return 2
    except KeyboardInterrupt:
        print("\ninterrupted.")
        return 130
    if os.name == "posix" and not os.access(albite, os.X_OK):
        print(f"error: {albite} is not executable (try: chmod +x {albite})")
        return 2

    profiles = available_profiles()
    targets = _resolve_targets(
        args.platforms or DEFAULT_PLATFORMS, args.profile, profiles
    )
    if targets is None:
        return 2

    glob_state = global_state(albite)
    can_preprocess = albite_supports_preprocess(albite)
    if not can_preprocess:
        _note(
            "this albite has no --preprocess-only, so edits inside #if blocks "
            "recompile every variant (see albite-preprocess-only.patch)."
        )
    failed = 0
    try:
        for target in targets:
            failed += build_target(target, args, glob_state, albite, can_preprocess)
    except KeyboardInterrupt:
        print(
            "\ninterrupted — running compiles were cancelled; "
            "shaders already finished stay cached."
        )
        return 130
    finally:
        shutil.rmtree(CACHE_DIR / "tmp", ignore_errors=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
