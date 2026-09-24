# workflow スキルの GitHub 操作スクリプト

SKILL.md の手順で繰り返し登場する、**ID を直接扱う GitHub Project 操作**を薄いラッパーにまとめる。
スクリプトは [`../config.yml`](../config.yml) から Project 番号・ID・Status の option-id を読むため、
手順書には生の ID を書かず、issue 番号・URL・Status 名を渡すだけでよい。

人間のゲート・herdr の worktree／パネル操作・モデル選択の判断など、状況判断を伴う部分は
スクリプト化せず SKILL.md の記述として残している（ここでは扱わない）。

## 実行環境・前提

- **シェル**: `bash`（`set -euo pipefail` を使用）
- **GitHub CLI**: `gh`。`gh auth login` 済みで、Project 操作には **project スコープ**が必要。
- **python3**: `gh --format json` の出力と config.yml の解釈に使用。
- リポジトリのルートから実行する（パス `.claude/skills/workflow/scripts/project.sh` で呼ぶ）。

## project.sh

```bash
bash .claude/skills/workflow/scripts/project.sh <サブコマンド> [引数...]
```

| サブコマンド | 引数 | 動作 |
| --- | --- | --- |
| `add-issue` | `<issue の URL>` | issue を Project に追加し、追加したアイテムの id を標準出力する |
| `set-status` | `<issue番号> <status>` | issue 番号から Project アイテムを引き、Status を指定の段階へ変更する |
| `active-issues` | （なし） | In Progress / In Review の issue 番号を列挙する（着手前の照合に使う） |

`<status>` は config.yml の `status_field.options` のキー
（`draft` / `backlog` / `in_progress` / `in_review` / `done`）。

環境変数 `WORKFLOW_CONFIG` で参照する config.yml のパスを上書きできる（既定はスキル直下の
`config.yml`）。

### 例

```bash
bash .claude/skills/workflow/scripts/project.sh add-issue https://github.com/asaty94/lyricord/issues/93
bash .claude/skills/workflow/scripts/project.sh set-status 93 in_review
bash .claude/skills/workflow/scripts/project.sh active-issues
```

## 別リポジトリへの適用

適用時に固有値を書き換える必要はない。`../config.yml` を [`../setup/init.sh`](../setup/init.sh) が
適用先の ID で生成・上書きするため、スクリプトはそのまま動く。適用手順は
[`../setup/README.md`](../setup/README.md) を参照。
