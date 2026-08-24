# OrbStack Linux machine

OrbStack の Linux machine（Ubuntu）を、mise / Docker Engine / Claude Code 入りで作るための
cloud-init 設定です。Claude Code には Playwright MCP を登録済みなので、そのまま
ブラウザ操作を頼めます。git や vim の設定も machine 専用のものが自動で入るので、
作り直しても設定し直す必要はありません。

- [`cloud-init.yaml`](cloud-init.yaml) — machine 作成時に渡す cloud-config

## 前提

- macOS に [OrbStack](https://orbstack.dev/) がインストールされていること
- `orb` / `orbctl` が PATH にあること（`orb version` で確認）
- ホスト側に `~/workspace` が存在すること（machine へマウントする作業ディレクトリ）

## 作成

`MACHINE` は任意の machine 名に読み替えてください。`-u` で仮想マシン側のユーザー名にも
同じ値を渡すので、machine 名とユーザー名は常に一致します。

```sh
MACHINE=dev

orbctl create \
  --isolated \
  -u "$MACHINE" \
  --mount ~/workspace:/home/"$MACHINE"/workspace \
  --user-data cloud-init.yaml \
  ubuntu "$MACHINE"
```

各オプションの意味:

| オプション | 意味 |
| --- | --- |
| `--isolated` | machine を隔離モードで作る。ホストのファイル共有と各種統合（macOS の `$HOME` 自動マウント、コマンド連携など）が無効になる |
| `-u`, `--user` | 作成する machine のデフォルトユーザー名を指定する。省略すると macOS 側のユーザー名になる |
| `--mount SOURCE:DEST` | 隔離モードの machine に、ホストのディレクトリを個別にマウントする。`--isolated` と併用する場合のみ有効 |
| `--user-data` | cloud-init の user data。`-c` でも同じ |

`--isolated` を付けると、そのままではホストのファイルは一切見えません。そこに
`--mount` で `~/workspace` だけを通しています。マウント先は明示が必要です
（macOS のホームは `/Users/$USER`、Linux 側は `-u` で指定した `/home/$MACHINE` で
パスが違うため、`~/workspace:~/workspace` とは書けません）。

なお `--isolated` だけならネットワークはホストや他の machine と通じたままです。
ネットワークも切りたい場合は `--isolate-network` を追加します。

セットアップ（apt のアップグレード、Docker、Claude Code、Playwright のインストール）は
`orbctl create` が返ってきた後もバックグラウンドで続きます。ブラウザのダウンロードがある分、
後処理は数分かかります。完了は次のように確認します。

```sh
# cloud-init 本体の完了待ち
orb -m "$MACHINE" -u root cloud-init status --wait

# ユーザー側の後処理（docker グループ追加、ユーザー設定、Claude Code、Playwright MCP）の完了待ち
orb -m "$MACHINE" -u root systemctl status provision-user.service
```

完了後の確認:

```sh
orb -m "$MACHINE" bash -lc 'mise --version; docker version; claude --version'
orb -m "$MACHINE" bash -lc 'claude mcp list'
orb -m "$MACHINE" ls -al /home/"$MACHINE"/workspace
```

`docker` を sudo なしで使うにはグループ変更の反映が必要なので、
`provision-user.service` の完了後に一度 machine を再起動してください。

```sh
orbctl restart "$MACHINE"
```

## 起動・停止

```sh
# 起動
orbctl start "$MACHINE"

# 停止
orbctl stop "$MACHINE"

# 再起動
orbctl restart "$MACHINE"

# 状態の確認（全 machine の一覧）
orbctl list
```

引数なしの `orbctl stop` は OrbStack サービス全体（Docker と全 machine）を止めてしまうので、
machine 名は必ず指定してください。

machine に入る／コマンドを実行する:

```sh
# シェルに入る
orb -m "$MACHINE"

# 単発でコマンドを実行する
orb -m "$MACHINE" uname -a

# root で実行する
orb -m "$MACHINE" -u root apt-get update
```

毎回 `-m` を書きたくない場合は、既定の machine を切り替えます。

```sh
orbctl default "$MACHINE"
```

## 削除

**machine 内のファイルは警告なしに完全に失われます。** ホストの `~/workspace` は
マウントしているだけなので消えませんが、machine のホーム配下（`~/.claude` など）は消えます。
machine は作り直すまで使い続けるものなので、残したい作業は `~/workspace` に置いてください。

```sh
# 確認プロンプトあり。停止中でもそのまま削除できる
orbctl delete "$MACHINE"

# 確認なしで削除
orbctl delete -f "$MACHINE"
```

## 補足: ユーザー設定

machine は必要になったら作り直すので、そのたびに手で設定し直さずに済むよう、
**この machine 専用の設定**を `cloud-init.yaml` の `write_files` に持っています。
ホストの dotfiles はマウントも clone もしません。設定を変えたいときは
`cloud-init.yaml` を編集します（既存の machine には反映されないので、
その場で直すか作り直すことになります）。

| 実体（`write_files`） | 配置先 |
| --- | --- |
| `/usr/local/share/machine-config/gitconfig` | `~/.gitconfig` |
| `/usr/local/share/machine-config/vimrc` | `~/.vimrc` |
| `/usr/local/share/machine-config/claude-settings.json` | `~/.claude/settings.json` |

デフォルトユーザーは cloud-init の完了後に作られるため、`write_files` では
ホーム配下に直接置けません。いったん `/usr/local/share/machine-config/` に置き、
`provision-user.sh` がユーザー出現後に所有者を付けて配置しています。

内容は「machine で最低限困らない」線に寄せてあります。

- `gitconfig` — コミットに必要な `user.name` / `user.email`、`core.editor = vim`、
  `core.quotepath = false`、`init.defaultBranch = main`、`color.ui = auto`、
  それと `co` / `ci` / `st` / `br` / `lg` / `ca` のエイリアス。
  末尾に `~/.gitconfig.local` の `[include]` があり、identity は後述の方法で上書きできる
- `vimrc` — 文字コード、シンタックス、行番号、インデント、検索まわりだけ
- `claude-settings.json` — `language` / `theme` / `tui` のほか、
  `skipDangerousModePermissionPrompt`（後述のエイリアス向け）や
  `cleanupPeriodDays` などの動作設定

`vim` は `packages` に追加してあります。Ubuntu の cloud image には `vim-tiny` しか
入っておらず、`core.editor = vim` が効かないためです。

### git の user.name / user.email を変える

`gitconfig` に入っている identity はこのリポジトリの持ち主のものです。`cloud-init.yaml` を
編集しなくても、machine 側の `~/.gitconfig.local` で上書きできます。

```sh
orb -m "$MACHINE" bash -lc "
  git config -f ~/.gitconfig.local user.name  'Your Name'
  git config -f ~/.gitconfig.local user.email 'you@example.com'
"
```

ホスト側の設定をそのまま持ち込むなら、こう書けます。

```sh
orb -m "$MACHINE" bash -lc "
  git config -f ~/.gitconfig.local user.name  '$(git config --get user.name)'
  git config -f ~/.gitconfig.local user.email '$(git config --get user.email)'
"
```

`~/.gitconfig` の末尾に `[include] path = ~/.gitconfig.local` があり、git は後に読んだ値を
優先するのでこちらが勝ちます。ファイルが存在しない場合は黙って無視されるため、
何もしなければデフォルトのままです。

machine を作り直すたびに実行する必要があります（`~/.gitconfig.local` は machine 内の
ファイルなので消えます）。毎回打ちたくなければ、`cloud-init.yaml` の `gitconfig` の
`[user]` を自分の値に書き換えてしまうのが早いです。

## 補足: claude のエイリアス

`/etc/profile.d/99-dev-env.sh` で、確認プロンプトを全部飛ばすエイリアスを張っています。

```sh
alias claude="claude --allow-dangerously-skip-permissions --permission-mode bypassPermissions"
```

machine 自体が隔離環境で、壊れても作り直せるので、この中では権限確認を省いています。
bash は非対話シェルでエイリアスを展開しないため、効くのは `orb -m "$MACHINE"` で
入った対話セッションだけです。`orb -m "$MACHINE" claude ...` のような単発実行では
展開されないので、その場合はフラグを直接渡してください。

素の `claude` を使いたいときは `\claude` または `command claude` で回避できます。

なお、この machine はホストや外部ネットワークへ出られます。権限確認を外すと
Claude Code の実行内容が一切止められなくなるので、machine の外に影響しうるもの
（マウントした `~/workspace` の中身、到達できるネットワーク先）は把握しておいてください。

## 補足: Playwright MCP

`provision-user.sh` で以下をまとめて済ませています。

- `mise use -g node@lts` — Claude Code は MCP サーバーを `npx` で起動するため、
  mise の shims が `npx` を解決できるよう node の global バージョンを固定する
- `npx playwright install-deps` — ヘッドレスブラウザの共有ライブラリ（root で実行）
- `npx @playwright/mcp install-browser chrome-for-testing` — ブラウザ本体。
  対象ユーザーの `~/.cache/ms-playwright` に入る
- `claude mcp add playwright --scope user ...` — MCP サーバー登録。user スコープなので
  `~/.claude.json` に書かれ、machine 内のどのディレクトリからでも使える

日本語のページが豆腐（□）にならないよう、`fonts-noto-cjk` を `packages` に入れています。

`--isolate-network` を付けて machine を作るとブラウザから外部サイトへ出られません。
Playwright を使うなら `--isolated` のみにしてください。

## 補足: ホームディレクトリの所有者

`--mount` のマウント先をホーム配下（`/home/$MACHINE/workspace`）にすると、OrbStack が親の
`/home/$MACHINE` を root 所有で先に作るため、ホームがユーザーから書けない状態になります。
Claude Code や mise は `$HOME` 配下にインストールするので、これは致命的です。

`cloud-init.yaml` の `provision-user.sh` でホームを chown し直しているため、
上記の手順どおりに作れば対処済みです。cloud-init を使わずに machine を作った場合は、
手動で直してください。

```sh
orb -m "$MACHINE" -u root chown "$MACHINE" /home/"$MACHINE"
```
