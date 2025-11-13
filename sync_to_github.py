#!/usr/bin/env python3
"""同步服务启动器（移植自 Astrbot-Napcat-huggingface）

运行后将：
- 启动同步守护进程（自动初始化/链接/周期提交推送）；
- 启动最小 Web 管理页面（端口 5321，前缀 /sync）。

需要环境：
- GITHUB_PAT: GitHub Token（repo 权限）
- GITHUB_REPO: 目标仓库（owner/repo）
- 可选：BASE（默认 /）、HIST_DIR（默认 /home/user/.sdv-backup）、SYNC_TARGETS（默认 data/）
"""
from sync.main import run_all


if __name__ == "__main__":
    raise SystemExit(run_all())

