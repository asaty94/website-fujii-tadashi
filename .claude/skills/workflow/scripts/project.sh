#!/usr/bin/env bash
#
# workflow スキルの GitHub Project 操作をまとめた薄いラッパー。
# config.yml から Project 番号・ID・Status の option-id を読み、
# ID を直接扱う gh コマンドを隠す。SKILL.md の各手順から呼び出す。
#
# 使い方（リポジトリのルートから実行する）:
#   bash .claude/skills/workflow/scripts/project.sh add-issue <issue の URL>
#   bash .claude/skills/workflow/scripts/project.sh set-status <issue番号> <status>
#   bash .claude/skills/workflow/scripts/project.sh active-issues
#
#   <status> は draft / backlog / in_progress / in_review / done のいずれか
#   （config.yml の status_field.options のキー）。
#
# 環境変数 WORKFLOW_CONFIG で参照する config.yml のパスを上書きできる。
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${WORKFLOW_CONFIG:-$SCRIPT_DIR/../config.yml}"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v gh >/dev/null      || die "gh (GitHub CLI) が見つかりません"
command -v python3 >/dev/null || die "python3 が見つかりません"
[ -f "$CONFIG" ] || die "config.yml が見つかりません: $CONFIG"

# config.yml からドット区切りキーの値を取り出す（2 階層のマッピング対応）。
#   cfg github.owner            -> lyricord
#   cfg status_field.options.draft -> 39799d8e
cfg() {
  python3 - "$CONFIG" "$1" <<'PY'
import re, sys
config_path, key = sys.argv[1], sys.argv[2]
stack, result = [], {}
for raw in open(config_path, encoding="utf-8"):
    line = raw.rstrip("\n")
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or stripped.startswith("-"):
        continue
    m = re.match(r"^(\s*)([^:]+):\s*(.*)$", line)
    if not m:
        continue
    indent, name, val = len(m.group(1)), m.group(2).strip(), m.group(3)
    val = re.sub(r"\s+#.*$", "", val).strip()  # 行末コメントを落とす
    while stack and stack[-1][0] >= indent:
        stack.pop()
    prefix = ".".join(n for _, n in stack)
    full = f"{prefix}.{name}" if prefix else name
    if val == "":
        stack.append((indent, name))
    else:
        result[full] = val
print(result.get(key, ""))
PY
}

# Project 内の全アイテムを JSON で取得する。
# item-list の --limit 既定値は 30 で取りこぼすため十分大きい値を渡す。
project_items_json() {
  gh project item-list "$(cfg github.project_number)" \
    --owner "$(cfg github.owner)" --format json --limit 1000
}

usage() {
  cat >&2 <<'EOF'
workflow スキルの GitHub Project 操作をまとめた薄いラッパー。

使い方（リポジトリのルートから実行する）:
  bash .claude/skills/workflow/scripts/project.sh add-issue <issue の URL>
  bash .claude/skills/workflow/scripts/project.sh set-status <issue番号> <status>
  bash .claude/skills/workflow/scripts/project.sh active-issues

  <status> は draft / backlog / in_progress / in_review / done のいずれか。
EOF
}

cmd="${1:-}"
[ $# -gt 0 ] && shift || true

case "$cmd" in
  # issue を Project に追加し、追加したアイテムの id を出力する。
  add-issue)
    [ $# -eq 1 ] || die "使い方: add-issue <issue の URL>"
    gh project item-add "$(cfg github.project_number)" \
      --owner "$(cfg github.owner)" --url "$1" --format json \
      | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])"
    ;;

  # issue 番号から Project アイテムを引き、Status を指定の段階へ変更する。
  set-status)
    [ $# -eq 2 ] || die "使い方: set-status <issue番号> <status>"
    num="$1"; key="$2"
    [[ "$num" =~ ^[0-9]+$ ]] || die "issue番号は数値で指定してください: $num"
    opt="$(cfg "status_field.options.$key")"
    [ -n "$opt" ] || die "未知の status: ${key}（draft/backlog/in_progress/in_review/done）"
    item="$(project_items_json \
      | python3 -c "import json,sys; items=json.load(sys.stdin)['items']; print(next((i['id'] for i in items if i.get('content',{}).get('number')==$num), ''))")"
    [ -n "$item" ] || die "issue #$num が Project に見つかりません"
    gh project item-edit --id "$item" \
      --project-id "$(cfg github.project_id)" \
      --field-id "$(cfg status_field.id)" \
      --single-select-option-id "$opt" >/dev/null
    echo "issue #$num の Status を $key にしました"
    ;;

  # In Progress / In Review の issue 番号を列挙する（着手前の照合に使う）。
  active-issues)
    [ $# -eq 0 ] || die "使い方: active-issues"
    project_items_json | python3 -c "
import json, sys
for i in json.load(sys.stdin)['items']:
    if i.get('status', '') in ('In Progress', 'In Review'):
        n = i.get('content', {}).get('number', '')
        if n != '':
            print(n)
"
    ;;

  ""|-h|--help|help)
    usage
    [ "$cmd" = "" ] && exit 2 || exit 0
    ;;

  *)
    die "未知のサブコマンド: ${cmd}（add-issue / set-status / active-issues）"
    ;;
esac
