# cc-sandbox

Claude Code を bypass permissions モードで安全に動かすための、ホスト（macOS / WSL2）から隔離された使い捨て開発サンドボックスを、一発コマンドで構築・破棄するツールです。

bypass permissions モードではコマンド実行やファイル削除が確認なしに走るため、ホスト上で直接使うと誤操作の影響がホストのファイルシステムやローカルサービスに及びます。cc-sandbox は Claude Code と開発ツール一式をコンテナに閉じ込め、マウントしたプロジェクトディレクトリの外側とホストのネットワークサービスに手が届かない状態を作ります。

## できること

- `cc-sandbox up <project-dir>` でサンドボックスインスタンスを起動し、指定したプロジェクトディレクトリだけを `/workspace` にマウント
- サンドボックスからホストのサービス（`127.0.0.1` / `0.0.0.0` バインドの両方）への到達を遮断しつつ、インターネットへの外向き通信は維持
- 認証プロファイル（`--profile`）で Claude Code の認証情報を注入するので、作り直しのたびに対話ログインする必要がない。名前を省略すると既存プロファイルから対話選択でき、`CC_SANDBOX_PROFILE` 環境変数（mise 等と組み合わせ可能）でプロジェクトごとに自動選択もできる
- code-server をランダムポート・localhost のみ・パスワード認証付きで公開
- DinD サイドカーにより、サンドボックス内で `docker run` や Testcontainers が使える（ホストの Docker デーモンは触らせない）
- Playwright MCP サーバーが同梱済みで、Claude Code が headless ブラウザで dev サーバーの画面を検証できる
- 複数インスタンスを同時起動でき、互いにネットワーク・ボリュームが分離される
- ツールキャッシュ（mise / uv / npm / Maven / Docker レイヤー / Playwright ブラウザ）は全インスタンス共通のボリュームに永続化され、作り直しても再ダウンロードが発生しない
- Claude Code のターンがユーザーへ戻ったら、ホストOSのネイティブ通知で気付ける（[ADR-0009](docs/adr/0009-turn-notification-via-host-watcher.md)）。bypass permissions で走らせたまま別作業をしていても見逃しにくい

## 前提条件

- Linux ネイティブまたは WSL2 の Docker（特権コンテナを起動できること）、あるいは macOS の OrbStack / Docker Desktop
- Bash
- Git（インストール時に `~/.cc-sandbox/src` へ clone するため）
- E2E テストを走らせる場合のみ [Bats](https://bats-core.readthedocs.io/)

## インストール

```sh
curl -fsSL https://raw.githubusercontent.com/backpaper0/cc-sandbox/main/install.sh | bash
```

リポジトリを `~/.cc-sandbox/src` に clone し（既にあれば `git pull` で更新）、`bin/cc-sandbox` を `~/.local/bin/cc-sandbox` へ symlink します（詳細は [ADR-0005](docs/adr/0005-install-script-fixed-clone-and-symlink.md)）。再実行すれば最新版に更新されます。`~/.local/bin` が PATH に無い場合は、追加すべき設定をインストーラが案内します。

インストール後は、この `curl | bash` を再実行する代わりに `cc-sandbox upgrade` でも最新版に更新できます（詳細は [ADR-0012](docs/adr/0012-upgrade-subcommand-ff-only-on-running-repo.md)）。

以降の使い方はすべて、インストール後に PATH の通った `cc-sandbox` コマンドを前提にしています。リポジトリ自体を手元に clone して開発している場合は、代わりに `bin/cc-sandbox` を直接実行してください。

## セットアップ：認証プロファイル

`--profile <name>` に対応する `~/.cc-sandbox/env.<name>` という、Git 管理外のローカル設定ファイルを用意します（詳細は [ADR-0003](docs/adr/0003-auth-injection-per-host-profile.md)）。`<name>` は固定の2択ではなく、英数字・`-`・`_` からなる任意の名前を付けられるので、私的用途／業務用途だけでなく案件・クライアントごとにプロファイルを分けることもできます。

私的環境（Claude サブスクリプション）— `~/.cc-sandbox/env.private`:

```sh
# ホスト側で一度だけ発行する
claude setup-token
```

```sh
CLAUDE_CODE_OAUTH_TOKEN=<setup-token で発行した長期トークン>
```

業務環境（Amazon Bedrock）— `~/.cc-sandbox/env.work`:

```sh
CLAUDE_CODE_USE_BEDROCK=1
AWS_BEARER_TOKEN_BEDROCK=<Bedrock の API キー>
AWS_REGION=us-east-1
```

案件ごとに認証情報を分けたい場合も、同じ形式で好きな名前のファイルを追加するだけです（例: `~/.cc-sandbox/env.client-a`）。

```sh
CLAUDE_CODE_USE_BEDROCK=1
AWS_BEARER_TOKEN_BEDROCK=<client-a 用の Bedrock API キー>
AWS_REGION=us-east-1
```

このファイルは `--profile` で指定したときだけ読み込まれ、本体コンテナに環境変数として注入されます。`~/.claude/.credentials.json` のマウントは行いません。

どんな名前のプロファイルを作ったか忘れてしまった場合は、`--profile` に値を渡さずに実行すると（`--profile` を末尾に置く、`--profile=` の後を空にするなど）、`~/.cc-sandbox/env.*` から見つかった名前を一覧表示し、対話的に選択できます（詳細は [ADR-0006](docs/adr/0006-interactive-profile-selection.md)）。候補が0件、非TTY環境、選択のキャンセルはいずれもエラー終了します。

### `CC_SANDBOX_PROFILE`：環境変数によるプロファイルの自動選択

複数のプロジェクトを掛け持ちしていて、プロジェクトごとに使うプロファイルが決まっている場合、`--profile` を毎回打つ代わりに `CC_SANDBOX_PROFILE` 環境変数をセットしておけます。`--profile` を省略したとき、この環境変数が空でなければその値がプロファイル名として使われます（詳細は [ADR-0010](docs/adr/0010-profile-selection-via-environment-variable.md)）。

[mise](https://mise.jdx.dev/) の `env` でディレクトリごとに環境変数を切り替えている場合、プロジェクトのルートに置いた `mise.toml` に1行足すだけで、そのディレクトリ配下に `cd` した瞬間から自動的に対応するプロファイルが使われるようになります。

```toml
# ~/project_a/mise.toml
[env]
CC_SANDBOX_PROFILE = "project_a"
```

```sh
cd ~/project_a/repo_1
cc-sandbox up .
# => Using profile: project_a (from $CC_SANDBOX_PROFILE)
```

明示的に `--profile <name>` を渡した場合（値を省略した対話選択を含む）は常にそちらが優先され、`CC_SANDBOX_PROFILE` は無視されます。`CC_SANDBOX_PROFILE` が指す `~/.cc-sandbox/env.<name>` が存在しない、または名前の文字種が不正な場合は、`--profile` を明示したときと同じくエラー終了します（黙ってプロファイルなしにフォールバックすることはありません）。

## セットアップ：企業CA証明書・プロキシ

企業ネットワークのTLS/SSL Inspection配下で使う場合、以下の2ファイルを置いておくとフラグなしで自動的に適用されます（詳細は [ADR-0007](docs/adr/0007-corporate-ca-and-proxy-per-host-file.md)）。`--profile` とは独立しており、同じホスト上で複数プロファイルを使い分けても設定は1箇所で済みます。

`~/.cc-sandbox/ca-cert.crt`（企業CA証明書、PEM1枚）:

```sh
cp /path/to/corporate-ca.pem ~/.cc-sandbox/ca-cert.crt
```

ビルド時に本体コンテナのシステムCA一式へマージされ、実行時にDinDサイドカーにも同じ証明書がインストールされます。mise管理のJDKには例外対応として、コンテナ起動のたびに専用のJavaトラストストアが生成されます。

`~/.cc-sandbox/proxy.env`（`HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY`）:

```sh
HTTP_PROXY=http://proxy.example.com:8080
HTTPS_PROXY=http://proxy.example.com:8080
NO_PROXY=localhost,127.0.0.1,.internal.example.com
```

本体コンテナ・DinDサイドカーの両方に注入され、イメージビルド時のパッケージ取得（BuildKitの自動プロキシ伝播）にも使われます。どちらのファイルも存在しなければ何も変わりません。

## 使い方

```
cc-sandbox up <project-dir> [--profile <name>] [--name <slug>] [--no-notify]
cc-sandbox down [project-dir] [--name <slug>]
cc-sandbox list
cc-sandbox exec [project-dir] [--name <slug>] [-- <command...>]
cc-sandbox password [project-dir] [--name <slug>]
cc-sandbox upgrade
```

### 起動

```sh
cc-sandbox up ~/work/my-project --profile private
```

案件ごとにプロファイルを分けている場合はその名前を指定します。

```sh
cc-sandbox up ~/work/client-a-project --profile client-a
```

名前を忘れた場合は値を省略すると一覧から選べます。

```sh
cc-sandbox up ~/work/my-project --profile
```

```
1) private
2) work
3) client-a
Select a profile: 1
Using profile: private
```

イメージのビルド、本体コンテナと DinD サイドカーの起動、ネットワーク隔離ルールの適用、code-server の起動待ちまでを行い、最後に接続情報を出力します。

```
Sandbox 'cc-sandbox-my-project-1a2b3c4d' is up.
  Project dir:  /Users/you/work/my-project -> /workspace
  Enter with:   docker exec -it -u dev <container-id> bash
  code-server:  http://127.0.0.1:54321
  Password:     docker exec -u dev <container-id> grep '^password:' /home/dev/.config/code-server/config.yaml
```

「通知ウォッチャー」（[ADR-0009](docs/adr/0009-turn-notification-via-host-watcher.md)）がホスト側でバックグラウンド自動起動し、Claude Code のターンがユーザーへ戻ったらホストOSのネイティブ通知を出します。不要な場合はインスタンス単位で無効化できます。

```sh
cc-sandbox up ~/work/my-project --profile private --no-notify
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
cc-sandbox up ~/work/my-project --name feature-a --profile private
cc-sandbox up ~/work/my-project --name feature-b --profile private
```

同じ名前を別のディレクトリに対して使おうとした場合は、既存インスタンスを黙って上書きせずエラーになります。

### 一覧

```sh
cc-sandbox list
```

```
NAME                           PROJECT DIR                                   CODE-SERVER            NOTIFY
my-project-1a2b3c4d            /Users/you/work/my-project                    127.0.0.1:54321        running
feature-a                      /Users/you/work/my-project                    127.0.0.1:54322        disabled
```

`NOTIFY` 列は通知ウォッチャーの状態です。`running`（稼働中）/ `disabled`（`--no-notify` で意図的に無効化）/ `down`（本来動くはずが停止している）のいずれかを示します。

### 破棄

```sh
cc-sandbox down ~/work/my-project   # ディレクトリで指定
cc-sandbox down --name feature-a    # --name で起動したものは --name で指定
cc-sandbox down                     # 動いているインスタンスが1つだけならこれで足りる
```

キャッシュ用の名前付きボリュームは削除されないので、次に `up` したときに再利用されます。指定に該当する起動中インスタンスがない場合は、成功したように見せずエラーになります。

### 起動中インスタンスへの接続

`up`の出力（`Enter with:`/`Password:`行）をコピペしなくても、`exec`/`password`から後で改めて取得・実行できます。対象インスタンスの指定方法は`down`と同じで、`<project-dir>`または`--name`、両方省略時は起動中インスタンスが1つだけならそれを使います。

```sh
cc-sandbox exec ~/work/my-project        # bashで入る
cc-sandbox exec --name feature-a         # --nameで起動したものを指定
cc-sandbox exec -- ls -la /workspace     # 任意コマンドを実行（--以降がそのまま渡る）
cc-sandbox password ~/work/my-project    # code-serverのパスワードの値だけを出力
```

### アップグレード

```sh
cc-sandbox upgrade
```

`curl | bash` を再実行しなくても、`cc-sandbox` コマンド自体を最新版に更新できます。今実行している `cc-sandbox` が属するリポジトリに対して `git pull --ff-only` するだけなので、`install.sh` でインストールした環境・開発クローンを直接実行している環境のどちらでも動きます（詳細は [ADR-0012](docs/adr/0012-upgrade-subcommand-ff-only-on-running-repo.md)）。

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

作業ユーザーは非 root の `dev` で、`apt-get`/`apt` に限りパスワードなしの `sudo` が使えます（[ADR-0008](docs/adr/0008-restrict-dev-sudo-to-package-management.md)）。`dev` にパスワードは設定されていないため、それ以外のコマンドへの `sudo` は実行できません。`docker` CLI は `DOCKER_HOST=tcp://dind:2375` 経由で DinD サイドカーのネストされた Docker デーモンを向いており、ホストの Docker デーモンには到達しません。

## 隔離の仕組み

**ファイルシステム**: bind mount するのはコマンド引数で渡したプロジェクトディレクトリ 1 つだけです（1 インスタンス = 1 プロジェクト）。`~/.ssh` や `~/.aws` などをマウントしない運用が前提で、CLI 側に除外機構はありません。

**ネットワーク**（[ADR-0004](docs/adr/0004-network-isolation-in-container-owner-match.md)）: コンテナ内部の iptables に、`dev` ユーザー（owner match）からホスト側アドレスへの新規接続を REJECT するルールを入れます。対象は RFC1918、リンクローカル `169.254.0.0/16`、CGNAT `100.64.0.0/10`、および実行時に解決した `host.docker.internal` のアドレスです（[sandbox/blocked-ranges.sh](sandbox/blocked-ranges.sh)）。ホスト側の iptables を触らないため、Linux ネイティブでも macOS の VM 経由の Docker でも同じコードパスで動き、`down` 時に後始末すべきルールも残りません。DinD サイドカー内で起動したコンテナにも、FORWARD チェーンに同等のルールを入れて同じ制約をかけます。

この隔離は「事故の防止」であって「脱出の防止」ではありません。`dev` の `sudo` はパッケージ管理コマンドのみに絞られていますが（[ADR-0008](docs/adr/0008-restrict-dev-sudo-to-package-management.md)）、`apt-get install` のインストールフックは root 権限で任意コード実行が可能なため、意図的にそれを悪用すればルールを外せます。この割り切りは ADR-0004 で明示的に受け入れたものです。

**code-server**: コンテナ内では `0.0.0.0:8080` にバインドしますが、ホスト側への公開は `127.0.0.1` のランダムポートに限定され、パスワード認証（初回起動時に自動生成）が必須です。

## Playwright MCP

Playwright MCP サーバーはイメージに焼き込まれ、ユーザースコープの MCP 設定として全インスタンスで有効になっています。プロジェクト側に `.mcp.json` を用意する必要はありません。headless Chromium で動き、主な検証対象は本体コンテナ上で開発者が起動する dev サーバー（localhost）です。VNC 等によるライブ目視は提供せず、Claude Code が取得するスクリーンショット / スナップショットを対話内で確認する運用です。

## テスト

```sh
bin/test-e2e
```

実際の Docker デーモンに対して `bin/cc-sandbox` の公開 CLI を叩く Bats ベースの受け入れテストで、Docker のモックは行いません。前提条件と対象プラットフォームの範囲は [docs/e2e-testing.md](docs/e2e-testing.md) を参照してください。

## ドキュメント

| ファイル | 内容 |
| :--- | :--- |
| [CONTEXT.md](CONTEXT.md) | ドメイン用語集（サンドボックス / 本体コンテナ / DinD サイドカー等） |
| [docs/adr/README.md](docs/adr/README.md) | アーキテクチャ決定記録の索引 |
| [docs/e2e-testing.md](docs/e2e-testing.md) | E2E テストの実行方法と対象プラットフォーム |
| [.scratch/isolated-dev-sandbox/spec.md](.scratch/isolated-dev-sandbox/spec.md) | 元の仕様（ユーザーストーリー・実装方針・スコープ外） |

## 既知の制約

- macOS（OrbStack / Docker Desktop）での `host.docker.internal` 迂回経路は、ルールとしては塞いでいるものの実機での検証は未実施です。受け入れの基準となるプラットフォームは WSL2 / Linux ネイティブ Docker です。
- 本体コンテナ内の root は隔離ルールを解除できます。`dev` も `apt-get install` のインストールフックを悪用すれば同様のことが可能です（[ADR-0008](docs/adr/0008-restrict-dev-sudo-to-package-management.md)）。悪意ある脱出への防御ではありません。
- IPv6 は対象外です（現状これらのコンテナに IPv6 アドレスとルートが割り当てられないため）。
- CI/CD 連携、監視・ロギング基盤、sysbox / rootless Docker への移行はスコープ外です。
