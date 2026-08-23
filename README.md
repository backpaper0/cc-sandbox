# cc-sandbox

Claude Code を bypass permissions モードで安全に動かすための、ホスト（macOS / WSL2）から隔離された使い捨て開発サンドボックスを、一発コマンドで構築・破棄するツールです。

bypass permissions モードではコマンド実行やファイル削除が確認なしに走るため、ホスト上で直接使うと誤操作の影響がホストのファイルシステムやローカルサービスに及びます。cc-sandbox は Claude Code と開発ツール一式をコンテナに閉じ込め、マウントしたプロジェクトディレクトリの外側とホストのネットワークサービスに手が届かない状態を作ります。

## できること

- `bin/sandbox up <project-dir>` でサンドボックスインスタンスを起動し、指定したプロジェクトディレクトリだけを `/workspace` にマウント
- サンドボックスからホストのサービス（`127.0.0.1` / `0.0.0.0` バインドの両方）への到達を遮断しつつ、インターネットへの外向き通信は維持
- 認証プロファイル（`--profile`）で Claude Code の認証情報を注入するので、作り直しのたびに対話ログインする必要がない
- code-server をランダムポート・localhost のみ・パスワード認証付きで公開
- DinD サイドカーにより、サンドボックス内で `docker run` や Testcontainers が使える（ホストの Docker デーモンは触らせない）
- Playwright MCP サーバーが同梱済みで、Claude Code が headless ブラウザで dev サーバーの画面を検証できる
- 複数インスタンスを同時起動でき、互いにネットワーク・ボリュームが分離される
- ツールキャッシュ（mise / uv / npm / Maven / Docker レイヤー / Playwright ブラウザ）は全インスタンス共通のボリュームに永続化され、作り直しても再ダウンロードが発生しない

## 前提条件

- Linux ネイティブまたは WSL2 の Docker（特権コンテナを起動できること）、あるいは macOS の OrbStack / Docker Desktop
- Bash
- E2E テストを走らせる場合のみ [Bats](https://bats-core.readthedocs.io/)

## セットアップ：認証プロファイル

ホストごとに、Git 管理外のローカル設定ファイルを用意します（詳細は [ADR-0003](docs/adr/0003-auth-injection-per-host-profile.md)）。

私的環境（Claude サブスクリプション）— `~/.sandbox/env.private`:

```sh
# ホスト側で一度だけ発行する
claude setup-token
```

```sh
CLAUDE_CODE_OAUTH_TOKEN=<setup-token で発行した長期トークン>
```

業務環境（Amazon Bedrock）— `~/.sandbox/env.work`:

```sh
CLAUDE_CODE_USE_BEDROCK=1
AWS_BEARER_TOKEN_BEDROCK=<Bedrock の API キー>
AWS_REGION=us-east-1
```

このファイルは `--profile` で指定したときだけ読み込まれ、本体コンテナに環境変数として注入されます。`~/.claude/.credentials.json` のマウントは行いません。

## 使い方

```
bin/sandbox up <project-dir> [--profile <private|work>] [--name <slug>]
bin/sandbox down [project-dir] [--name <slug>]
bin/sandbox list
```

### 起動

```sh
bin/sandbox up ~/work/my-project --profile private
```

イメージのビルド、本体コンテナと DinD サイドカーの起動、ネットワーク隔離ルールの適用、code-server の起動待ちまでを行い、最後に接続情報を出力します。

```
Sandbox 'sandbox-my-project-1a2b3c4d' is up.
  Project dir:  /Users/you/work/my-project -> /workspace
  Enter with:   docker exec -it -u dev <container-id> bash
  code-server:  http://127.0.0.1:54321
  Password:     docker exec -u dev <container-id> grep '^password:' /home/dev/.config/code-server/config.yaml
```

サンドボックスに入って Claude Code を起動するには:

```sh
docker exec -it -u dev <container-id> bash
claude
```

サンドボックス内の `claude` は素のセッション起動（引数なし・プロンプト・`-p` 等）に対して自動で `--dangerously-skip-permissions --permission-mode bypassPermissions` を付与します。`claude mcp` 等のサブコマンドや、自分で権限系フラグを指定した呼び出しはそのまま素通しされます。

隔離ルールの適用や DinD・code-server の起動に失敗した場合、`up` は中途半端な状態を残さず自動でインスタンスを破棄して異常終了します（隔離なしで立ち上がったサンドボックスはサンドボックスではないため）。

### 名前付きインスタンス

`--name` を付けると、プロジェクトディレクトリではなく明示したスラッグでインスタンスを識別します。同じディレクトリに対して複数のインスタンスを並行させたいときに使います。

```sh
bin/sandbox up ~/work/my-project --name feature-a --profile private
bin/sandbox up ~/work/my-project --name feature-b --profile private
```

同じ名前を別のディレクトリに対して使おうとした場合は、既存インスタンスを黙って上書きせずエラーになります。

### 一覧

```sh
bin/sandbox list
```

```
NAME                           PROJECT DIR                                   CODE-SERVER
my-project-1a2b3c4d            /Users/you/work/my-project                    127.0.0.1:54321
feature-a                      /Users/you/work/my-project                    127.0.0.1:54322
```

### 破棄

```sh
bin/sandbox down ~/work/my-project   # ディレクトリで指定
bin/sandbox down --name feature-a    # --name で起動したものは --name で指定
bin/sandbox down                     # 動いているインスタンスが1つだけならこれで足りる
```

キャッシュ用の名前付きボリュームは削除されないので、次に `up` したときに再利用されます。指定に該当する起動中インスタンスがない場合は、成功したように見せずエラーになります。

## サンドボックスの中身

本体コンテナ（`ubuntu:24.04` ベース、[sandbox/Dockerfile](sandbox/Dockerfile)）には以下が入っています。

| ツール | 備考 |
| :--- | :--- |
| Claude Code | バージョン固定でグローバルインストール。`claude` コマンドは bypass permissions を自動付与するラッパー経由（[使い方](#使い方)参照） |
| mise | Python 3.12 / Node.js 22 / Java (temurin-21) をグローバル設定 |
| uv | Python パッケージマネージャ |
| Playwright + Playwright MCP | ユーザースコープの MCP サーバーとして登録済み、Chromium 同梱 |
| code-server | エントリポイントでバックグラウンド起動 |
| Vim / git / build-essential / docker CLI | |

作業ユーザーは非 root の `dev` で、パスワードなしの無制限 `sudo` が使えます。`docker` CLI は `DOCKER_HOST=tcp://dind:2375` 経由で DinD サイドカーのネストされた Docker デーモンを向いており、ホストの Docker デーモンには到達しません。

## 隔離の仕組み

**ファイルシステム**: bind mount するのはコマンド引数で渡したプロジェクトディレクトリ 1 つだけです（1 インスタンス = 1 プロジェクト）。`~/.ssh` や `~/.aws` などをマウントしない運用が前提で、CLI 側に除外機構はありません。

**ネットワーク**（[ADR-0004](docs/adr/0004-network-isolation-in-container-owner-match.md)）: コンテナ内部の iptables に、`dev` ユーザー（owner match）からホスト側アドレスへの新規接続を REJECT するルールを入れます。対象は RFC1918、リンクローカル `169.254.0.0/16`、CGNAT `100.64.0.0/10`、および実行時に解決した `host.docker.internal` のアドレスです（[sandbox/blocked-ranges.sh](sandbox/blocked-ranges.sh)）。ホスト側の iptables を触らないため、Linux ネイティブでも macOS の VM 経由の Docker でも同じコードパスで動き、`down` 時に後始末すべきルールも残りません。DinD サイドカー内で起動したコンテナにも、FORWARD チェーンに同等のルールを入れて同じ制約をかけます。

この隔離は「事故の防止」であって「脱出の防止」ではありません。`dev` は無制限の sudo を持つため、root になれば自分でルールを外せます。この割り切りは ADR-0004 で明示的に受け入れたものです。

**code-server**: コンテナ内では `0.0.0.0:8080` にバインドしますが、ホスト側への公開は `127.0.0.1` のランダムポートに限定され、パスワード認証（初回起動時に自動生成）が必須です。

## Playwright MCP

Playwright MCP サーバーはイメージに焼き込まれ、ユーザースコープの MCP 設定として全インスタンスで有効になっています。プロジェクト側に `.mcp.json` を用意する必要はありません。headless Chromium で動き、主な検証対象は本体コンテナ上で開発者が起動する dev サーバー（localhost）です。VNC 等によるライブ目視は提供せず、Claude Code が取得するスクリーンショット / スナップショットを対話内で確認する運用です。

## テスト

```sh
bin/test-e2e
```

実際の Docker デーモンに対して `bin/sandbox` の公開 CLI を叩く Bats ベースの受け入れテストで、Docker のモックは行いません。前提条件と対象プラットフォームの範囲は [docs/e2e-testing.md](docs/e2e-testing.md) を参照してください。

## ドキュメント

| ファイル | 内容 |
| :--- | :--- |
| [CONTEXT.md](CONTEXT.md) | ドメイン用語集（サンドボックス / 本体コンテナ / DinD サイドカー等） |
| [docs/adr/README.md](docs/adr/README.md) | アーキテクチャ決定記録の索引 |
| [docs/e2e-testing.md](docs/e2e-testing.md) | E2E テストの実行方法と対象プラットフォーム |
| [.scratch/isolated-dev-sandbox/spec.md](.scratch/isolated-dev-sandbox/spec.md) | 元の仕様（ユーザーストーリー・実装方針・スコープ外） |

## 既知の制約

- macOS（OrbStack / Docker Desktop）での `host.docker.internal` 迂回経路は、ルールとしては塞いでいるものの実機での検証は未実施です。受け入れの基準となるプラットフォームは WSL2 / Linux ネイティブ Docker です。
- 本体コンテナ内の root（および sudo 経由の `dev`）は隔離ルールを解除できます。悪意ある脱出への防御ではありません。
- IPv6 は対象外です（現状これらのコンテナに IPv6 アドレスとルートが割り当てられないため）。
- CI/CD 連携、監視・ロギング基盤、sysbox / rootless Docker への移行はスコープ外です。
