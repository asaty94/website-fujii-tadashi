# workflow スキルの適用先セットアップ

この workflow スキルを**新しいリポジトリ**へ適用するための前提・初期設定手順・実行環境をまとめる。
`init.sh` が GitHub Project・Status フィールドを作成し、生成された ID を
[`../config.yml`](../config.yml) へ書き出す。手作業で ID を扱う必要はない。

## 適用手順（概要）

1. このスキルのディレクトリ（`.claude/skills/workflow/`）を、適用先リポジトリの同じ場所へコピーする。
2. 適用先リポジトリのルートで [`init.sh`](init.sh) を実行する（下記「初期設定手順」）。
   `config.yml` が適用先の ID で上書きされる。
3. 「スクリプトで作らない前提」（フォルダ構成・テンプレート・組み込みワークフロー）を手で用意する。

## 実行環境・前提

- **シェル**: `bash`（`set -euo pipefail` を使用）
- **GitHub CLI**: `gh`。`gh auth login` 済みで、かつ **project スコープ**が必要。
  未付与なら `gh auth refresh -s project --hostname github.com` を実行する。
- **python3**: JSON の解釈に使用（`gh` の `--format json` 出力をパースする）。
- 適用先のリポジトリが GitHub 上に存在し、`gh` から読み書きできること。
- GitHub Project（user/org の Projects v2）を作成できる権限があること。

## 初期設定手順

適用先リポジトリのルートで実行する。

```bash
bash .claude/skills/workflow/setup/init.sh \
  --owner <login> \
  --repo <owner/name> \
  --title "<Project のタイトル>" \
  [--commander-agent <agent 名>] \
  [--config-out <出力先 config.yml のパス>]
```

| 引数 | 必須 | 説明 |
| --- | --- | --- |
| `--owner` | ✓ | Project のオーナー（`gh` の `--owner`）。ユーザー名または org 名 |
| `--repo` | ✓ | 適用先リポジトリ。`owner/name` 形式（司令AI agent 名の既定値の導出に使う） |
| `--title` | ✓ | 作成する GitHub Project のタイトル |
| `--commander-agent` | | 司令AI の herdr agent 名。未指定ならリポジトリ名を使う |
| `--config-out` | | 書き出し先 `config.yml` のパス。未指定ならスキル直下の `config.yml` |

スクリプトが行うこと:

1. **GitHub Project を作成**し、番号と ID を取得する。
2. デフォルトの **Status フィールドを削除**し、`Draft / Backlog / In Progress / In Review / Done`
   の 5 段階を持つ **Status フィールドを作り直す**。
3. 作成した Status フィールドの ID と各選択肢の ID を読み戻す。
4. 上記で得た ID とオーナー名・agent 名を `config.yml` へ書き出す。

## スクリプトで作らない前提（手で用意する）

ID を伴わない、またはスクリプト化しにくい前提は手作業で用意する。

- **フォルダ構成と各 README（分類基準）**: 成果物・記録などの置き場所と分類基準。
  フォルダによる分類はフォルダ構成と各 README で表現し（分類基準の正本は各 README）、
  フォルダ配下の細分類もフォルダと README で表現する。
  具体的なフォルダ名・粒度は適用先リポジトリの方針に合わせて決める
  （スキル本体は特定のフォルダ名を前提とせず、置き場所の判断はこの分類基準に委ねる）。
  各 README に「どのフォルダへ何を置くか」の分類基準を書く（分類基準の正本）。
- **Issue / PR テンプレート**: `.github/ISSUE_TEMPLATE/issue.md` と
  `.github/PULL_REQUEST_TEMPLATE.md`。本文の 5 セクション構成の書式は `SKILL.md` に記載。
- **AI モデル使い分け基準の記録**: 決定を残すフォルダ（分類基準に従う）に記録として残す
  （作業パネルのモデル選択の運用ルール自体は `SKILL.md` に自己完結で記載）。適用先の方針に合わせて用意する。
- **Project の組み込みワークフロー「Item closed → Status: Done」**:
  GitHub Project の UI（Project → 右上「⋯」→ Workflows）で有効化する。
  issue を close すると自動で Status が Done になる挙動はこの組み込みワークフローに依存し、
  `gh` CLI からは設定できないため手動で有効化する。

これらは適用先リポジトリ側で用意する前提であり、スキル本体（`.claude/skills/workflow/`）からは参照しない。

## 適用後の確認

```bash
cat .claude/skills/workflow/config.yml                 # ID が書き込まれているか
gh project field-list <project_number> --owner <owner> --format json   # Status の 5 選択肢
```

問題なければ [`../SKILL.md`](../SKILL.md) の手順でワークフローを回せる。
