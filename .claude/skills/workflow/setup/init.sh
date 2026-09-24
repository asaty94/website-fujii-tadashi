#!/usr/bin/env bash
#
# workflow スキルの初期化スクリプト。
# 新しい適用先リポジトリで GitHub Project・Status フィールドを作成し、
# 生成された ID を config.yml へ書き出す。
#
# 実行環境・前提・使い方は同じディレクトリの README.md を参照。
#
# 使い方:
#   bash init.sh \
#     --owner <login> \
#     --repo <owner/name> \
#     --title "<Project のタイトル>" \
#     [--commander-agent <agent 名>] \
#     [--config-out <出力先 config.yml のパス>]
#
set -euo pipefail

# --- 引数の解釈 -------------------------------------------------------------

OWNER=""
REPO=""
TITLE=""
COMMANDER_AGENT=""
# デフォルトの出力先はこのスクリプトの 1 つ上（スキルのルート）の config.yml
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_OUT="$SCRIPT_DIR/../config.yml"

usage() {
  sed -n '3,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --owner)           OWNER="$2"; shift 2 ;;
    --repo)            REPO="$2"; shift 2 ;;
    --title)           TITLE="$2"; shift 2 ;;
    --commander-agent) COMMANDER_AGENT="$2"; shift 2 ;;
    --config-out)      CONFIG_OUT="$2"; shift 2 ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "ERROR: 未知の引数: $1" >&2; usage; exit 2 ;;
  esac
done

die() { echo "ERROR: $*" >&2; exit 1; }

[ -n "$OWNER" ] || die "--owner は必須です"
[ -n "$REPO" ]  || die "--repo は必須です（owner/name 形式）"
[ -n "$TITLE" ] || die "--title は必須です"
# 司令AI の agent 名は未指定ならリポジトリ名を使う
[ -n "$COMMANDER_AGENT" ] || COMMANDER_AGENT="${REPO##*/}"

# --- 前提チェック -----------------------------------------------------------

command -v gh >/dev/null      || die "gh (GitHub CLI) が見つかりません"
command -v python3 >/dev/null || die "python3 が見つかりません"
gh auth status >/dev/null 2>&1 || die "gh が未認証です。'gh auth login' を実行してください"
# Project の作成には project スコープが要る
if ! gh auth status 2>&1 | grep -q "project"; then
  die "gh のトークンに project スコープがありません。'gh auth refresh -s project --hostname github.com' を実行してください"
fi

echo ">> Project を作成します: owner=$OWNER title=$TITLE"

# --- 1. Project の作成 ------------------------------------------------------

PROJECT_JSON="$(gh project create --owner "$OWNER" --title "$TITLE" --format json)"
PROJECT_NUMBER="$(echo "$PROJECT_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['number'])")"
PROJECT_ID="$(echo "$PROJECT_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")"
PROJECT_URL="$(echo "$PROJECT_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['url'])")"
echo "   number=$PROJECT_NUMBER id=$PROJECT_ID"
echo "   $PROJECT_URL"

# --- 2. Status フィールドの ID を取得 ---------------------------------------
# 新規 Project には Todo/In Progress/Done のデフォルト Status フィールドが付く。
# このフィールドは組み込みのため削除できない（Only custom fields can be deleted）。
# そこで選択肢だけを我々の 5 段階に置き換える。

STATUS_FIELD_ID="$(gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" --format json \
  | python3 -c "
import json,sys
for f in json.load(sys.stdin)['fields']:
    if f.get('name') == 'Status':
        print(f['id']); break
")"
[ -n "$STATUS_FIELD_ID" ] || die "デフォルトの Status フィールドが見つかりません"

# --- 3. Status の選択肢を 5 段階へ置き換える --------------------------------
# updateProjectV2Field の singleSelectOptions は既存の選択肢を丸ごと置き換える。

echo ">> Status の選択肢を設定します: Draft / Backlog / In Progress / In Review / Done"
MUTATION_JSON="$(gh api graphql -f fieldId="$STATUS_FIELD_ID" -f query='
mutation($fieldId: ID!) {
  updateProjectV2Field(input: {
    fieldId: $fieldId
    singleSelectOptions: [
      {name: "Draft",       color: GRAY,   description: ""},
      {name: "Backlog",     color: BLUE,   description: ""},
      {name: "In Progress", color: YELLOW, description: ""},
      {name: "In Review",   color: ORANGE, description: ""},
      {name: "Done",        color: GREEN,  description: ""}
    ]
  }) {
    projectV2Field {
      ... on ProjectV2SingleSelectField { id options { id name } }
    }
  }
}')"

# --- 4. 置き換えた選択肢の ID を読み取る ------------------------------------
# 選択肢名から ID を引く（name は引数で渡す。ブレース展開を避けるため dict は使わない）。

opt_id() {
  echo "$MUTATION_JSON" | python3 -c "
import json, sys
opts = json.load(sys.stdin)['data']['updateProjectV2Field']['projectV2Field']['options']
print(next((o['id'] for o in opts if o['name'] == '$1'), ''))
"
}
OPT_DRAFT="$(opt_id 'Draft')"
OPT_BACKLOG="$(opt_id 'Backlog')"
OPT_IN_PROGRESS="$(opt_id 'In Progress')"
OPT_IN_REVIEW="$(opt_id 'In Review')"
OPT_DONE="$(opt_id 'Done')"
for k in DRAFT BACKLOG IN_PROGRESS IN_REVIEW DONE; do
  v="OPT_$k"
  [ -n "${!v:-}" ] || die "Status 選択肢 $k の ID を取得できませんでした"
done
echo "   field=$STATUS_FIELD_ID draft=$OPT_DRAFT backlog=$OPT_BACKLOG in_progress=$OPT_IN_PROGRESS in_review=$OPT_IN_REVIEW done=$OPT_DONE"

# --- 5. config.yml を書き出す -----------------------------------------------

echo ">> config.yml を書き出します: $CONFIG_OUT"
cat > "$CONFIG_OUT" <<EOF
# .claude/skills/workflow/config.yml
# このリポジトリに固有の設定値。setup/init.sh が生成する。
# SKILL.md の各手順が参照する。値を変更する際はこのファイルのみ更新する。
# 値は秘匿情報ではないためコミット可。

# GitHub Project
github:
  owner: $OWNER
  project_number: $PROJECT_NUMBER
  project_id: $PROJECT_ID

# Project の Status フィールド
status_field:
  id: $STATUS_FIELD_ID
  options:
    draft:       $OPT_DRAFT
    backlog:     $OPT_BACKLOG
    in_progress: $OPT_IN_PROGRESS
    in_review:   $OPT_IN_REVIEW
    done:        $OPT_DONE

# 司令AIのエージェント名（herdr agent send の宛先）
commander_agent: $COMMANDER_AGENT
EOF

cat <<EOF

完了しました。
  Project: $PROJECT_URL
  config : $CONFIG_OUT

次の手動ステップ（README.md 参照）:
  - Project の組み込みワークフロー「Item closed → Status: Done」を UI で有効化する
  - フォルダ構成と各 README（分類基準）を用意する（フォルダ名は適用先リポジトリの方針に合わせる）
  - Issue/PR テンプレートを用意する（モデル使い分けの運用ルールは SKILL.md に記載済み）
EOF
