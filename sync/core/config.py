"""配置与路径映射（移植）

读取环境变量：GITHUB_PAT/GITHUB_REPO/HIST_DIR/GIT_BRANCH/SYNC_TARGETS/EXCLUDE_PATHS/BASE
提供路径映射工具。
"""

import os
from dataclasses import dataclass
from typing import List, Dict, Any


DEFAULT_BASE = os.environ.get("BASE", "/")
DEFAULT_HIST_DIR = os.environ.get("HIST_DIR", "/home/steam/.sdv-backup")
DEFAULT_BRANCH = os.environ.get("GIT_BRANCH", "main")

# 默认只同步星露谷存档目录（Saves）
DEFAULT_TARGETS = (
    os.environ.get("SYNC_TARGETS", "home/steam/.config/StardewValley/Saves/").strip().split()
)

DEFAULT_EXCLUDES = (
    os.environ.get("EXCLUDE_PATHS", "").strip().split()
)


@dataclass
class Settings:
    base: str
    hist_dir: str
    branch: str
    github_pat: str
    github_repo: str
    targets: List[str]
    excludes: List[str]
    ready_file: str


def _load_file_overrides(hist_dir: str) -> Dict[str, Any]:
    import json
    cfg_path = os.path.join(hist_dir, "sync-config.json")
    try:
        with open(cfg_path, "r", encoding="utf-8") as f:
            obj = json.load(f)
            if isinstance(obj, dict):
                return obj
    except FileNotFoundError:
        pass
    except Exception:
        pass
    return {}


def save_file_overrides(hist_dir: str, data: Dict[str, Any]) -> None:
    import json
    os.makedirs(hist_dir, exist_ok=True)
    cfg_path = os.path.join(hist_dir, "sync-config.json")
    with open(cfg_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def load_settings() -> Settings:
    base = DEFAULT_BASE.rstrip("/") or "/"
    hist_dir = os.path.abspath(DEFAULT_HIST_DIR)
    branch = DEFAULT_BRANCH
    github_pat = os.environ.get("GITHUB_PAT", "")
    github_repo = os.environ.get("GITHUB_REPO", "")
    targets = list(DEFAULT_TARGETS)
    excludes = list(DEFAULT_EXCLUDES)

    overrides = _load_file_overrides(hist_dir)
    if isinstance(overrides.get("targets"), list) and overrides["targets"]:
        targets = [str(x).lstrip("/") for x in overrides["targets"] if str(x).strip()]
    if isinstance(overrides.get("excludes"), list):
        ex = [str(x).strip("/") for x in overrides["excludes"] if str(x).strip()]
        if ex:
            excludes = ex

    ready_file = os.environ.get("SYNC_READY_FILE", os.path.join(hist_dir, ".sync.ready"))

    return Settings(
        base=base,
        hist_dir=hist_dir,
        branch=branch,
        github_pat=github_pat,
        github_repo=github_repo,
        targets=targets,
        excludes=excludes,
        ready_file=ready_file,
    )


def to_abs_under_base(base: str, rel: str) -> str:
    if rel.startswith("/"):
        return rel
    if base == "/":
        return "/" + rel
    return os.path.normpath(os.path.join(base, rel))


def to_under_hist(hist: str, rel: str) -> str:
    rel = rel.lstrip("/")
    return os.path.normpath(os.path.join(hist, rel))
