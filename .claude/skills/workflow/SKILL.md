---
name: workflow
description: "issue 起票から PR マージまでを回すシンプルなワークフロー。main セッションで作業依頼（ファイルの追加・変更・設定など）を受けたら、直接作業せずこのスキルに従う。main セッション＝司令AIは「新 issue 着手前の完了照合・main 最新化・worktree 削除」「issue 対応時のパネル作成・セッション作成・指示」だけを担い、レビュー依頼〜修正〜マージは issue ごとの作業パネル内で完結させる。人間のゲートは issue レビュー・PR レビュー（動作確認を含む）の 2 つ。"
---

このスキルは **司令AI**（main checkout の herdr セッション）と **作業AI**（issue ごとに切る worktree のパネル）の 2 役で回す。セッションを開始したら、まず次の「役割の自己判定」で自分がどちらかを確定し、共通の参照節（役割分担・前提・命名規則・設定・Status・モデル選定）を押さえたうえで、**自分の役の「手順」だけ**を読んで実行する。

## 役割の自己判定

自分がどちらの役かは、git の worktree 種別で機械的に確定できる。**main checkout なら司令AI、linked worktree なら作業AI**：

```bash
git rev-parse --git-dir | grep -q '/worktrees/' && echo 作業AI || echo 司令AI
```

| コマンドの結果 | 役割 | 主なシグナル | 読む「手順」 |
| --- | --- | --- | --- |
| `司令AI` | **司令AI** | git-dir が `.git`／ブランチ `main`／herdr agent 名 `lyricord`／人間から直接「作業依頼」を受けて動く | 「手順（司令AI）」だけ |
| `作業AI` | **作業AI** | git-dir が `…/worktrees/…`／ブランチ `task/<N>-<slug>`／herdr agent 名 `task-<N>-<slug>`／司令AIから「issue #N を実施してください」のキックオフ指示を受けて動く | 「手順（作業AI）」だけ |

判定に迷ったら上記コマンドの結果を最優先とする（起動のされ方・パネル名・ディレクトリなどの状況シグナルは補助）。相手の役の「手順」は読まなくてよい。

## 役割分担

**人間**（ゲートは人間が持つ 2 つだけ）：
- ゲート①：issue レビュー（Draft の issue を確認し、OK を伝える）
- ゲート②：PR レビュー（作業パネルで PR を確認し、OK を伝える。動作に関わる変更では、PR 本文の動作確認手順を実行して動作確認とレビューをまとめて行う）

**司令AI（main セッション）**：
- issue の起票と Status 管理
- issue 対応時：worktree・ブランチ・パネル・セッションの作成と指示（**これらの作成は司令AIだけが行う**）
- 完了時（新しい issue に着手する直前に Project を照合して検知）：ローカル main を最新化し、worktree・パネルを削除する
- 作業パネルのレビュー依頼はユーザーに中継しない（レビュー〜マージはパネル内で完結する）

**作業AI（作業パネル）**：
- issue の実施と PR 作成（PR 作成前に origin/main を取り込む）
- 動作に関わる変更は、PR 作成前にまず自分で動作を確かめ、人間がそのまま実行できる動作確認手順を PR 本文の「動作確認手順」節（検証内容の次）に箇条書きで書く（人間は PR レビュー（ゲート②）で動作確認とレビューをまとめて行う）
- そのパネル内でのレビュー依頼・修正対応・OK 後のマージ
- worktree・ブランチ・作業パネルは司令AIが作成済みの状態で作業を始める。worktree・ブランチ・パネルの作成・分割（`herdr worktree create`・`git switch -c`・`herdr pane split` など）は実行しない

## 前提

- **main では直接作業せず**、issue に取り組むときに初めて herdr で worktree を切る
- 1 worktree＝1 issue＝1 ブランチ＝1 PR。並行数の上限は設けない
- worktree は同一リポジトリを共有するため、`git fetch` すれば全 worktree から最新の `origin/main` が見える。ただし **作業中のブランチへの取り込みはその worktree の agent 自身が行う**（外から rebase をかけない）
- herdr CLI の構文確認は **引数なしでサブコマンドを実行して usage を確認する**（例：`herdr worktree`）。`--help` / `-h` は未知のオプション扱いで使えない。usage が表示されても終了コードは非ゼロのため「Error」と表示されるが、構文確認としては成功している
- AI モデルの使い分けは本手順書の「モデル選定」節のルーブリックに従う。**司令AIセッションは人間が `claude --model opus` で起動する**。作業パネルのモデルは、起票時に独立したモデル選定サブエージェントが issue の内容から判定した結果（issue に記録され、人間が必要なら上書き可能）を、司令AIが起動時に適用する

## 命名規則

### ブランチ

```
task/<issue番号>-<slug>
```

`<slug>` は英小文字ケバブケース（例：`task/84-branch-naming`）。複数 issue を 1 ブランチで統合対応する場合は issue 番号をハイフンでつなげてからスラッグを付ける（例：`task/38-44-foo-bar`）。

### 作業パネル名（herdr の agent／workspace 名）

作業パネル名はブランチ名のスラッシュをハイフンに置き換えた**正規化形**に一致させる（herdr の名前にはスラッシュを使えないため）：

| ブランチ名 | 作業パネル名 |
| --- | --- |
| `task/84-branch-naming` | `task-84-branch-naming` |
| `task/38-44-foo-bar` | `task-38-44-foo-bar` |

作業パネル内でブランチを切り替えた場合は、パネル名（agent・workspace の名前）も新しいブランチの正規化形に追従してリネームする（「手順（司令AI）」の「複数 issue を 1 パネルで統合対応する場合」の rename コマンドを参照）。

## 設定

このスキルに固有の値（GitHub Project ID・Status option-id・オーナー名・司令AI agent 名など）は [config.yml](config.yml) に集約されています。

Project への追加・Status の遷移・item id の取得など、**ID を直接扱う GitHub 操作は [scripts/project.sh](scripts/project.sh) にまとめてあります**。このスクリプトが config.yml を読んで `gh` コマンドを組み立てるため、各手順では issue 番号や URL・Status 名（`draft` / `backlog` / `in_progress` / `in_review` / `done`）を渡すだけでよく、生の ID を手順書に書く必要はありません。スクリプトの使い方は [scripts/README.md](scripts/README.md) を参照。人間のゲート・herdr の worktree／パネル操作・モデル選択の判断など、状況判断を伴う部分はスクリプト化せず手順書の記述として残しています。

このスキルを**別のリポジトリへ適用する**ときは、スキルのディレクトリをコピーして [setup/README.md](setup/README.md) の手順に従う。`setup/init.sh` が GitHub Project・Status を作成し、生成した ID を config.yml へ書き出す。

## Status

| Status | 意味 |
| --- | --- |
| Draft | 起票直後・人間の確認待ち（**作業対象外**） |
| Backlog | 人間の OK 済み。**作業できるのは Backlog の issue のみ** |
| In Progress | 着手したら変更する |
| In Review | PR 作成直後に手動で変更する（`project.sh set-status <N> in_review`） |
| Done | issue の close で自動的に変更される（close → Done は自動化済み。手動での変更は不要） |

Status の変更は [scripts/project.sh](scripts/project.sh) の `set-status <issue番号> <status>` で行う（スクリプトが config.yml の `github.project_id`・`status_field.id`・`status_field.options.*` を読んで `gh project item-edit` を組み立てる）。

## モデル選定

作業パネルのモデルは、issue の内容（タスクの認知的負荷）にもとづき、次のルーブリックで段階を決める。フォルダやラベルではなくタスクの中身で判定する：

| 段階 | モデル | 目安 |
| --- | --- | --- |
| 通常 | `sonnet` | 仕様が明確で局所的・機械的な作業（定型のファイル操作・書式修正・単純な追記・既定手順どおりの制作など） |
| 賢い | `opus` | 設計・方針の判断、広範な影響、深い推論を要する作業 |
| 最上位 | `fable` | 後戻りしにくい重要判断や事業の方向性を決める検討（大きな契約・法務・多額の支出・事業設計の根幹） |

**判定に迷ったら賢い側に倒す**（通常か賢いで迷えば賢い、賢いか最上位で迷えば最上位とする）。

### 判定の委譲（独立サブエージェント）

判定は起票者（司令AI）とは別の**独立したサブエージェント**に委ね、判定のぶれと起票者のバイアスを減らす。全 issue を判定対象とする。

- **入力**：issue の目的・対応方法・完了条件
- **出力**：構造化して返す（`段階`＝通常／賢い／最上位、`理由`）
- **起動モデル**：判定を全 issue で 1 回ずつ回すため、**消費の小さい軽量モデル（`haiku`）**で動かす。司令AIが Task（Agent）ツールでサブエージェントを起動する際に、`model` に `haiku` を指定し、上記ルーブリックと issue 内容をプロンプトに渡して単発で判定させる（隔離コンテキストで結果を 1 つ返す使い方）
- **定義の置き場所**：ルーブリックと判定手順はこの SKILL.md に自己完結で置き、司令AIが起動時にインラインで渡す（`.claude/agents/` に別ファイルは作らない）。ルーブリックの正本をこの手順書 1 か所に保ち、二重管理と乖離を避けるため

### 確定・記録・上書き

- **3 段階（通常／賢い／最上位）いずれも判定でそのまま確定**する（最上位も含めて人間の承認は不要）。
- 判定結果（段階・理由）は issue の備考に記録し、人間が可視化して、必要なら段階を上書きできる（承認は求めないが、違うと思えば上書きできる導線を残す）。上書きされた段階が起動時の最終値になる。

### フォールバック

サブエージェントが使えない・未整備のときは、司令AIが同じルーブリックで自分で判定する。**迷ったら賢い側（`opus`）に倒す**。

## 手順（司令AI）

**この節は司令AI（main checkout）だけが読む。** 作業AI は「手順（作業AI）」へ進む。司令AI は原則 1 → 2 → 3 の順で進め、issue が完了したら 4 を行う。

### 1. 作業依頼を受けたら（現状把握のみ）

作業依頼（ファイルの追加・変更・設定など）を受けたら、**直接作業を始めず**、現状把握のみ行う（読み取り系の操作のみ可。ファイルの作成・変更・コピーはしない）。把握した内容をもとに issue を起票して **Draft** にし、人間の OK（ゲート①）で **Backlog** になってから worktree で作業する。

**例外**：次の操作は司令AIが worktree を切らずに直接行ってよい：

- push・ローカル main の最新化（`git pull --ff-only`）
- issue の起票・本文更新・close、Project の Status 変更
- herdr の worktree・パネル・セッション操作（作成・指示・監視）

### 2. issue 起票（Status: Draft）

issue を起票し、Project に追加して Status を **Draft** にし、リンクを人間に提示して確認を依頼する。人間の OK（ゲート①）が出たら Status を **Backlog** にする。

本文は次の 5 セクション構成で書く：

- **目的・対応方法・完了条件**：リンクを使わず、誰でもわかる簡易な文章で書く。他のファイルを参照しなくても内容がわかる自己完結した記載にし、ファイル名・手順番号・コマンド名などの具体的な参照は関連か備考に書く
- **関連**：関連 issue・参照ドキュメントへのリンクはここにまとめる
- **備考**：リンクや具体的な参照を使わずに書いたことで上のセクションに書ききれなかった詳細・補足はここに書く

**成果物の置き場所を決める**：起票時に、この対応で作成・変更するファイルとその置き場所を対応方法に明記する。置き場所はリポジトリの分類基準（各フォルダの README 等）に従い、分類基準の本体はここに転記しない（正本はリポジトリ側にある）。

**調査・検討の issue**：調査・検討の issue は、検討結果を文書として残すことを対応方法に必ず含める。置き場所（決定した基準・方針と、調査・ヒアリングの記録の区別を含む）はリポジトリの分類基準に従う。

**モデル判定（独立サブエージェント）**：起票内容（目的・対応方法・完了条件）が固まったら、司令AIは「モデル選定」節の手順に従い、独立したモデル選定サブエージェント（軽量モデル `haiku`）を起動して段階を判定させる。判定結果（段階・理由）を issue の備考へ次の形式で記録する：

```
- モデル判定: <通常/賢い/最上位>（<sonnet/opus/fable>）／理由: <理由>
```

3 段階いずれもそのまま確定する（最上位も含めて人間の承認は不要）。人間は必要なら記録された段階を上書きできる（上書き後の段階が着手時の最終値になる）。

```bash
gh issue create --title "<タイトル>" --body "<本文>"
bash .claude/skills/workflow/scripts/project.sh add-issue <issue の URL>   # Project に追加（item id を出力）
bash .claude/skills/workflow/scripts/project.sh set-status <N> draft        # Status → Draft（人間の確認待ち）
# 人間の OK（ゲート①）が出たら：
bash .claude/skills/workflow/scripts/project.sh set-status <N> backlog      # Status → Backlog
```

### 3. Backlog の issue に着手 → worktree・作業パネルを作成して指示

着手できるのは **Backlog の issue のみ**。着手したら Status を **In Progress** にする。

**着手前に照合する**：worktree を作る前に、Project の In Progress・In Review アイテムを確認し、close 済みのものがあれば「4. 完了照合 → main 最新化・worktree 削除」の処理を先に行う。完了検知はこのタイミングのみ（真の即時反映はセッションが入力駆動のため不可。必要なら別途フックや定期ポーリングが要る）。

```bash
bash .claude/skills/workflow/scripts/project.sh active-issues   # In Progress / In Review の issue 番号を列挙
# 表示された issue が close 済みなら「4. 完了照合 …」を実行してからここに戻る
```

claude の起動前に、司令AIは issue の備考に記録されたモデル判定（「2. issue 起票」で独立サブエージェントが判定し、必要なら人間が上書き済み）の段階からモデルを選ぶ：通常＝`sonnet`／賢い＝`opus`／最上位＝`fable`。判定が記録されていない・サブエージェントが使えなかった場合は、司令AIが「モデル選定」節のルーブリックで自分で判定し、**迷ったら賢い側（`opus`）**に倒す。

```bash
bash .claude/skills/workflow/scripts/project.sh set-status <N> in_progress   # Status → In Progress（着手）
git fetch origin                                              # 最新の origin/main から切るため
herdr workspace list                                          # 親 workspace id を確認
herdr worktree create --workspace <親ws> --label "task-<N>-<slug>" --no-focus --json   # root_pane.pane_id を控える
git -C <worktree> switch -c task/<N>-<slug> origin/main
git worktree list                                             # create の出力は信用せず git で実体確認
herdr pane run <root_pane.pane_id> "claude --model <選択>"    # ルートパネルで claude を起動（新パネルは作らない）。<選択> は上記の基準で選んだ sonnet / opus / fable
herdr agent rename <root_pane.pane_id> task-<N>-<slug>        # 以降は task-<N>-<slug> 名で操作する
herdr agent send task-<N>-<slug> "issue #<N> を実施してください。ブランチは task/<N>-<slug>（worktree・ブランチとも作成済み・checkout 済みの状態で作業が始まります。作成コマンドの実行は不要です）。動作に関わる変更の場合は、まず自分で動作を確かめたうえで、人間がそのまま実行できる動作確認手順を PR 本文の「動作確認手順」節（検証内容の次）に箇条書きで書いてください（人間は PR レビュー時に動作確認とレビューをまとめて行います）。PR 作成前に git fetch origin && git rebase origin/main で最新の main を取り込んでください。完了したら PR を作成し、このパネルで人間にレビューを依頼してください。修正指示にはこのパネルで対応し、人間から PR OK が出たら gh pr merge <PR番号> --squash --delete-branch でマージまで行ってください。マージが完了したら、workflow スキル「手順（作業AI）」の「マージ完了後の司令塔への通知（best-effort）」に従い、司令塔のパネル（agent 名 lyricord）へ herdr agent send で 1 行通知を送ってください（best-effort。届かなくても司令塔は issue の close で完了を検知するため、通知が失敗しても追加対応は不要です）。"
herdr pane send-keys <pane> enter
```

**指示送信後の確認**：指示文を送って送信キーを押したら、`herdr pane read` でパネルの画面を読み、実行が始まったこと（スピナー表示や `herdr agent get` で agent_status が working になっていること）を確認する。指示文が入力欄に残ったままなら `herdr pane send-keys <pane> enter` を再送する。なお claude の起動直後は TUI が接続中（`/rc connecting…` 表示）のことがあり、その間の Enter は無視されるため、接続表示が消えるのを待ってから指示を送る。

`herdr agent start` は使わない（ペイン分割で 2 つ目のパネルを作ってしまうため）。`worktree create` が作るルートパネル 1 つだけで完結させる。rename 後は、指示送信（`agent send`）・状態監視（`agent wait`）・出力確認（`agent read`）のいずれも従来どおり `task-<N>-<slug>` 名で使える。

#### 複数 issue を 1 パネルで統合対応する場合

1 つの作業パネルで複数の issue を統合対応することにしたら、司令AIがブランチを `task/<N1>-<N2>-<slug>` 形式に切り替え、パネル（workspace）と agent の名前もその正規化形 `task-<N1>-<N2>-<slug>` に合わせてリネームする。例：`task/38-foo` のブランチで #44 も対応するなら、ブランチを `task/38-44-foo` に切り替え、パネル名も `task-38-44-foo` にそろえる。パネル名だけで、どの issue がそこで対応されているか分かる状態を保つ。

```bash
herdr workspace rename <workspace_id> task-<N1>-<N2>-<slug>
herdr agent rename <target> task-<N1>-<N2>-<slug>
```

また、司令AIがユーザーに報告する際は、どのパネルでどの issue を対応しているかを毎回明示する。

### 4. 完了照合 → main 最新化・worktree 削除

完了の検知は**新しい issue に着手する直前**（「3. Backlog の issue に着手」冒頭の照合）に行う（真の即時反映はセッションが入力駆動のため不可。必要なら別途フックや定期ポーリングが要る）。close 済みの issue を特定したら、次の処理を行う：

```bash
gh issue view <N> --json state                                # state が CLOSED になっていることを確認
git pull --ff-only                                            # main checkout を origin/main に追従させる

# task-<N>-<slug> に対応する worktree の workspace_id を特定する
herdr workspace list   # is_linked_worktree が true かつ label が task-<N>-<slug> の workspace を探す

herdr worktree remove --workspace <task_ws_id>               # git worktree を削除し herdr リンクを解除
herdr workspace close <task_ws_id>                           # パネルを閉じる
```

司令AIが行うのは次の 3 つ **だけ**：

1. issue の close 確認（`gh issue view <N> --json state`）
2. ローカル main の最新化（`git pull --ff-only`）
3. worktree・パネルの削除（`herdr worktree remove` → `herdr workspace close`）

Status の Done への変更は不要（issue close → Done は自動化済み）。作業中の他の worktree への反映は司令AIからは行わない（各 worktree の agent が PR 作成前に自分で取り込む）。`herdr agent wait --status idle` による完了待ちは使わない（agent の idle は「PR を作ってレビュー待ちで停止」と「マージ後に完了して停止」を区別できないため）。

## 手順（作業AI）

**この節は作業AI（worktree パネル）だけが読む。** 司令AI から「issue #N を実施してください」のキックオフ指示を受けて開始する。原則 1 → 2 の順で進める。

### 1. issue を実施する

指示を受けたら issue の内容を実施する。**PR を作成する前に `git fetch origin && git rebase origin/main` で最新の main を取り込む**。

動作に関わる変更（コマンド・スクリプト・スキル手順など）を含む場合は、PR を作成する前に **作業AI自身がその動作が実際にできることを確かめる**。そのうえで、人間がそのまま実行できる具体的な動作確認手順を PR 本文の「動作確認手順」節（検証内容の次）に、誰が見ても対応できるよう箇条書きで書く。独立した動作確認ゲートは設けず、人間は PR レビュー（ゲート②）でこの手順を実行して動作確認とレビューをまとめて行う。動作を伴わない変更（ドキュメントのみなど）は自分で動作確認する対象がないため、そのまま PR 作成に進んでよい。

worktree・ブランチ・作業パネルは司令AIが作成済みの状態で始まる。worktree・ブランチ・パネルの作成・分割（`herdr worktree create`・`git switch -c`・`herdr pane split` など）は実行しない。

### 2. PR 作成〜レビュー〜マージ（作業パネル内で完結）

作業AIが PR の URL を提示してレビューを依頼し、人間がそのパネルで修正指示・PR OK（ゲート②）を伝える。動作に関わる変更では、人間は PR 本文の動作確認手順を実行して動作確認とレビューをまとめて行い、OK を伝える。OK が出たら作業AIがマージする。

PR 本文は次の 6 セクション構成で書く（「手順（司令AI）」の「2. issue 起票」で示した issue 本文の書式と対になる PR 版のルール）：

- **背景・変更内容・検証内容**：リンク（issue 番号を含む）を使わず、誰でもわかる平易な文章で書く。背景は対応する issue の内容を読み取って書く。検証内容は作業AI自身がどう確かめたかを書く
- **動作確認手順**：検証内容の次に置く。動作に関わる変更のとき、人間がそのまま実行できる動作確認手順を、**誰が見ても対応できるよう箇条書きで書く**（実行するコマンド・確認する画面や出力・期待する結果）。独立した動作確認ゲートは設けないため、人間はこの手順を PR レビュー（ゲート②）で実行して動作確認とレビューをまとめて行う。作業AIは PR を作る前に自分でこの手順を実行して動作を確かめておく。動作を伴わない変更（ドキュメントのみなど）は、この節に「動作確認なし」と記載する
- **関連**：関連 issue・参照ドキュメントへのリンクはここにまとめる。`Closes #<N>` の記載もここに置く
- **備考**：上の 4 セクションに書けなかった内容（参考元との差分の理由・注意点など）はここに書く

PR を作成したら、直後に Status を **In Review** に変更する。スクリプトが issue 番号から item id を引いて設定する：

```bash
bash .claude/skills/workflow/scripts/project.sh set-status <N> in_review   # Status → In Review
```

PR 作成後のパネル報告は次の 1 行のみとする：

```
PR「<タイトル>」#<N> を作成しました: <URL>
```

作業内容の要約・レビュー依頼の定型文・動作確認手順・マージ手順の説明は書かない。作業内容とレビューすべき点は PR 本文でわかるため、パネル側の報告と重複させない。

レビュー指摘を受けて追加コミットを push したときのパネル報告は、PR タイトル・リンク・更新内容（何を変えたか）を 1〜2 文のみとする：

```
PR「<タイトル>」#<N>（<URL>）を更新しました。<更新内容を 1〜2 文で>
```

レビュー依頼の定型文・マージ手順の説明は書かない。

**司令AIは作業AIのレビュー依頼をユーザーに中継しない**。レビュー〜マージはパネル内で完結し、レビュー依頼の通知も作業AI側から人間に届くため、司令AIが PR 作成時点で報告すると二重報告になる。

#### マージ完了後の司令塔への通知（best-effort）

完了検知の正本は司令塔側の **close 照合**（司令AIが次の issue 着手前に issue の close を確認して完了を検知する。「手順（司令AI）」の 3・4 と [commander-report-after-close] の方針）。この通知はその補助であり、**届かなくても close で確実に検知される**（best-effort）。

マージが完了したら、司令塔のパネル（agent 名 `lyricord`）へ **herdr CLI の `herdr agent send`** で 1 行通知を送る：

```bash
herdr agent list                                              # name=lyricord が addressable か確認（司令AIの main パネル）
herdr agent send lyricord "issue #<N> の対応が完了しました（PR #<PR番号> をマージ）。"
herdr pane send-keys <lyricord のpane_id> enter               # agent send は入力欄に載せるだけなので Enter で送信（pane_id は上の agent list で確認）
```

**宛先解決のポイント**：宛先は必ず **herdr CLI（`herdr agent send <宛先>`）** で送る。`SendMessage` など別経路では司令塔を宛先解決できず「No agent named 'lyricord' is currently addressable」で失敗することがある。`herdr agent list` に `name` が `lyricord` の agent（司令AIの main checkout パネル）が出ていれば addressable。宛先名の正本は [config.yml](config.yml) の `commander_agent`。

**フォールバック**：`herdr agent list` に `lyricord` が出ない・`agent send` が失敗するなど通知が届かなくても、**追加の対応は不要**。司令塔は次の issue 着手前に issue の close で完了を検知するため、通知漏れで完了検知が漏れることはない。無理に別経路（`SendMessage` など）へ切り替えたり再送を繰り返したりしない。
