# cc-sandbox

Claude Code を安心して動かすためのサンドボックス環境を構築するアセット群。

[OrbStack](https://orbstack.dev/) 上にホストから隔離された Ubuntu マシンを作成し、[mise](https://mise.jdx.dev/) の `mise bootstrap` で開発ツールと dotfiles をまとめてセットアップする。

## 前提条件

ホスト（macOS）に以下が入っていること。

- OrbStack（`orb` / `orbctl` コマンド）
- Git（`user.name` と `user.email` が設定済みであること。マシン内の `~/.gitconfig` に引き継がれる）

## 使い方

### マシンを作成・プロビジョニングする

```sh
MACHINE_NAME="pirateship" MACHINE_USER="ichimi" ./provisioning/orbstack/provisioning.sh
```

| 環境変数 | 説明 |
| --- | --- |
| `MACHINE_NAME` | 作成する OrbStack マシンの名前 |
| `MACHINE_USER` | マシン内に作成するユーザー名 |

スクリプトは次の処理を行う。

1. マシンが存在しなければ `orbctl create` で作成する（ネットワーク隔離・ホストからの隔離を有効化し、パスワードを設定する）
2. `provisioning/scripts/` と `mise-bootstrap/` を tar で固めてマシンへ転送・展開する
3. マシン内で `install-mise.sh` を実行する（mise が入っていなければ、ユーザー権限で `~/.local/bin/mise` にインストールし、`~/.bashrc` に `mise activate` を追記する）
4. ホストの Git ユーザー情報を渡して、マシン内で `run-mise-bootstrap.sh` を実行する（`mise bootstrap`）
5. 転送した一時ファイルを削除する

マシンが既に存在する場合は作成をスキップし、プロビジョニングのみを再実行する。設定を変更したときに再適用する用途にも使える。

### マシンに入る

```sh
orb -m "$MACHINE_NAME"
```

### マシンを削除する

```sh
orbctl delete "$MACHINE_NAME"
```

## マシン内での操作

### パッケージ・ツールを一括更新する

```sh
upgrade-all
```

apt パッケージ、mise 本体と mise 管理のツール、uv 管理の Python、Claude Code をまとめて更新する。

## セットアップされる内容

### パッケージ・ツール

| 種類 | 内容 |
| --- | --- |
| apt | Docker（`docker-ce`、buildx、compose プラグイン）、git、vim、`fonts-noto-cjk` |
| mise | herdr、jq、uv |
| その他 | Claude Code（公式インストーラー）、uv 管理の Python（デフォルト） |

ユーザーは `docker` グループに追加され、Docker サービスは起動・自動起動が有効になる。

### 設定ファイル

| 配置先 | ソース | 備考 |
| --- | --- | --- |
| `~/.claude/settings.json` | `dotfiles/claude/settings.json` | 日本語設定、ライトテーマ、Remote Control 無効など |
| `~/.claude/statusline.sh` | `dotfiles/claude/statusline.sh` | モデル名・コンテキスト使用率・コスト（USD/JPY）・レート制限を表示 |
| `~/.config/herdr/config.toml` | `config/herdr/config.toml` | herdr（コーディングエージェント向けターミナルマルチプレクサ）の設定 |
| `~/.config/mise/config.toml` | `config/mise/config.toml` | グローバルに使うツール |
| `~/.config/uv/uv.toml` | `config/uv/uv.toml` | 公開から 24 時間未満のパッケージを除外、Python は uv 管理版のみ使用 |
| `~/.gitconfig` | `dotfiles/gitconfig.tera` | テンプレート。ホストの Git ユーザー情報を埋め込む |
| `~/.vimrc` | `dotfiles/vimrc` | ちょっとした編集向けの最小構成 |
| `~/.local/bin/upgrade-all` | `bin/upgrade-all` | 一括更新スクリプト |

パスはいずれも `mise-bootstrap/` からの相対パス。

## ディレクトリ構成

```
.
├── mise-bootstrap/         # mise bootstrap の設定一式（マシンへ転送される）
│   ├── mise.toml           # パッケージ・サービス・タスク・dotfiles の定義
│   ├── bin/                # ~/.local/bin に配置するスクリプト
│   ├── config/             # ~/.config 配下に配置する設定
│   └── dotfiles/           # ホームディレクトリ配下に配置するファイル
└── provisioning/
    ├── scripts/                    # プロビジョニング対象のマシン上で実行するスクリプト（OrbStack 非依存）
    │   ├── install-mise.sh         # mise をユーザー権限でインストールする
    │   └── run-mise-bootstrap.sh   # mise-bootstrap/ の設定で mise bootstrap を実行する
    └── orbstack/
        └── provisioning.sh         # OrbStack マシンの作成・転送・スクリプトの呼び出し
```

## OrbStack 以外の環境で使う

`provisioning/scripts/` のスクリプトは OrbStack に依存しない（Ubuntu / Debian 系を想定）。
`provisioning/scripts/` と `mise-bootstrap/` を対象マシンへ転送し、マシン上で次のように実行する。

```sh
./provisioning/scripts/install-mise.sh
GIT_USER_NAME="..." GIT_USER_EMAIL="..." ./provisioning/scripts/run-mise-bootstrap.sh ./mise-bootstrap
```

## カスタマイズ

- 入れるパッケージやツールを変えたい場合は `mise-bootstrap/mise.toml`（apt パッケージ）または `mise-bootstrap/config/mise/config.toml`（mise ツール）を編集する
- 配置するファイルを増やす場合は `mise-bootstrap/mise.toml` の `[dotfiles]` または `[bootstrap.files]` に追記する
- 変更後は `provisioning.sh` を再実行すると既存マシンに反映される
