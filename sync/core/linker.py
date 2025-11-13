from __future__ import annotations

import os
import shutil
import subprocess
from typing import Iterable

from sync.core.blacklist import is_excluded
from sync.core.config import to_abs_under_base, to_under_hist
from sync.utils.logging import log


def _rsync_available() -> bool:
    return shutil.which("rsync") is not None


def ensure_symlink(src: str, dst: str) -> None:
    parent = os.path.dirname(src)
    if parent:
        log(f"确保父目录存在: {parent}")
        os.makedirs(parent, exist_ok=True)

    if os.path.islink(src):
        cur = os.readlink(src)
        if cur == dst:
            log(f"符号链接已存在且正确: {src} -> {dst}")
            return
        log(f"更新符号链接 {src}: {cur} -> {dst}")
        os.unlink(src)
    elif os.path.exists(src):
        log(f"删除已存在的路径: {src} (isdir={os.path.isdir(src)})")
        if os.path.isdir(src):
            shutil.rmtree(src)
        else:
            os.remove(src)

    try:
        os.symlink(dst, src)
        log(f"✓ 符号链接已创建: {src} -> {dst}")
    except OSError as e:
        log(f"✗ 符号链接创建失败: {src} -> {dst}, 错误: {e}")
        raise


def migrate_and_link(base: str, hist_dir: str, rel_targets: Iterable[str]) -> None:
    for rel in rel_targets:
        log(f"处理目标: {rel}")
        rel_clean = rel.rstrip("/")
        src = to_abs_under_base(base, rel_clean)
        dst = to_under_hist(hist_dir, rel_clean)
        log(f"  src={src}, dst={dst}")
        os.makedirs(os.path.dirname(dst), exist_ok=True)

        if os.path.islink(src):
            log(f"  {src} 已是符号链接")
            ensure_symlink(src, dst)
            continue

        if os.path.isdir(src):
            log(f"  {src} 是目录，开始迁移")
            os.makedirs(dst, exist_ok=True)
            if _rsync_available():
                subprocess.run(["rsync", "-a", f"{src}/", f"{dst}/"], check=False)
            else:
                for root, dirs, files in os.walk(src):
                    relp = os.path.relpath(root, src)
                    dstd = os.path.join(dst, relp) if relp != "." else dst
                    os.makedirs(dstd, exist_ok=True)
                    for fn in files:
                        s = os.path.join(root, fn)
                        t = os.path.join(dstd, fn)
                        if not os.path.exists(t):
                            shutil.copy2(s, t)
            log(f"  删除原目录: {src}")
            shutil.rmtree(src, ignore_errors=True)
            ensure_symlink(src, dst)
        elif os.path.isfile(src):
            log(f"  {src} 是文件，开始迁移")
            if not os.path.exists(dst):
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.move(src, dst)
            else:
                os.remove(src)
            ensure_symlink(src, dst)
        else:
            log(f"  {src} 不存在，创建空目标")
            if rel.endswith("/"):
                log(f"  是目录（以/结尾），创建空目录: {dst}")
                os.makedirs(dst, exist_ok=True)
            else:
                log(f"  是文件（无/结尾），创建空文件: {dst}")
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                if not os.path.exists(dst):
                    open(dst, "a").close()
            ensure_symlink(src, dst)


def precreate_dirlike(hist_dir: str, rel_targets: Iterable[str]) -> None:
    for rel in rel_targets:
        rel_clean = rel.rstrip("/")
        dst = to_under_hist(hist_dir, rel_clean)
        if rel.endswith("/"):
            os.makedirs(dst, exist_ok=True)
        else:
            os.makedirs(os.path.dirname(dst), exist_ok=True)


def track_empty_dirs(hist_dir: str, rel_targets: Iterable[str], excludes: Iterable[str]) -> int:
    written = 0
    for rel in rel_targets:
        rel_clean = rel.rstrip("/")
        root = to_under_hist(hist_dir, rel_clean)
        if os.path.isdir(root):
            for d, subdirs, files in os.walk(root):
                rel_under_hist = os.path.relpath(d, hist_dir).lstrip("./")
                if is_excluded(rel_under_hist, excludes):
                    continue
                if "/.git/" in f"/{rel_under_hist}/":
                    continue
                if not os.listdir(d):
                    keep = os.path.join(d, ".gitkeep")
                    if not os.path.exists(keep):
                        open(keep, "a").close()
                        written += 1
    return written

