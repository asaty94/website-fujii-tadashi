#!/bin/bash
# Claude Code のステータスライン表示（#259）。
#
# Claude Code が stdin に渡すセッション情報 JSON（model / context_window /
# rate_limits / workspace 等）から次を 1 行にして返す：
#   モデル名｜CTX コンテキスト使用率｜5h サブスク使用率(残り時間)｜週 同(残り)｜git ブランチ
# python3 のみ使用（追加インストール不要）。スクリプトが失敗した場合は
# ステータスラインが空になるだけで、作業には影響しない。
#
# - CTX: セッションのコンテキストウィンドウ消費。緑 <60% / 黄 60–79% / 赤 80%〜
#   （赤＝コンパクションが近い）
# - 5h / 週: サブスク（Pro/Max）のレート制限ウィンドウ消費と、リセットまでの残り時間。
#   色分けは CTX と同じ閾値。rate_limits はサブスク利用時のみ渡される（無ければ非表示）

python3 -c '
import json, subprocess, sys, time

d = json.load(sys.stdin)

def colored(pct, label, extra=""):
    p = int(pct)
    color = "\033[31m" if p >= 80 else ("\033[33m" if p >= 60 else "\033[32m")
    return f"{color}{label} {p}%\033[0m{extra}"

parts = []

# モデル名
parts.append((d.get("model") or {}).get("display_name")
             or (d.get("model") or {}).get("id") or "?")

# コンテキスト使用率
pct = (d.get("context_window") or {}).get("used_percentage")
parts.append("CTX --%" if pct is None else colored(pct, "CTX"))

# サブスクのレート制限（5時間・週次）。used_percentage とリセットまでの残り時間
def remaining(epoch):
    secs = max(0, int(epoch - time.time()))
    if secs >= 86400:
        return f"残{secs // 86400}日"
    if secs >= 3600:
        return f"残{secs // 3600}:{(secs % 3600) // 60:02d}"
    return f"残{secs // 60}分"

rl = d.get("rate_limits") or {}
for key, label in (("five_hour", "5h"), ("seven_day", "週")):
    w = rl.get(key) or {}
    p = w.get("used_percentage")
    if p is None:
        continue
    ra = w.get("resets_at")
    extra = f"({remaining(ra)})" if ra else ""
    parts.append(colored(p, label, extra))

# git ブランチ
cwd = (d.get("workspace") or {}).get("current_dir") or "."
try:
    branch = subprocess.run(["git", "-C", cwd, "branch", "--show-current"],
                            capture_output=True, text=True, timeout=2).stdout.strip()
except Exception:
    branch = ""
if branch:
    parts.append(branch)

print(" | ".join(parts))
'
