# Claude Codeのサンドボックス

Claude Codeを安全に`--dangerously-skip-permissions`付きで動かすためのサンドボックス。

## 特徴

- Dockerコンテナに閉じ込めることで、予期せぬファイル更新・削除を防ぐ(例: `rm -fr $HOME`など)
- `internal`なDockerネットワークに閉じ込めることで、予期せぬ通信を防ぐ(例: 怪しいウェブサイトへのPOSTリクエストなど)
- bindマウントは最低限、ワークスペースとして扱うディレクトリのみ
- インターネット通信は`internal`なネットワークと`internal`でないネットワークの両方へ接続しているSquidコンテナを経由して行う
- ホスト側はVSCode等のエディタで該当ディレクトリを開いてClaude Codeが作成・編集したファイルを確認する

![](./architecture.drawio.svg)

## 前提条件

- Dockerがインストール済みかつ起動していること

## インストール

このリポジトリを`git clone`する。

```bash
git clone https://github.com/backpaper0/claude-code-environment.git
```

パスが通っている場所へシンボリックリンクを作成する。

```bash
ln -s $PWD/claude-in-sandbox $HOME/.local/bin/claude-in-sandbox
```

## 起動

作業対象のディレクトリへ移動してコマンドを実行する。

```bash
cd /path/to/your/project
claude-in-sandbox
```

実行すると必要に応じてコンテナイメージの作成、Dockerネットワークの作成、Squidコンテナの起動などを行い、Claude Codeが動くコンテナが起動する。
カレントディレクトリがコンテナ内の `/workspaces/<ディレクトリ名>` としてマウントされ、作業ディレクトリとなる。

## 初回認証

コンテナ起動後、初回は Claude Code のログインが必要になる。

```bash
claude
```

を実行すると認証フローが始まるので、案内に従って Anthropic アカウントでログインする。
認証情報はホスト側の `~/.claude-in-sandbox` ディレクトリに保存されるため、2回目以降は再認証不要。

## カスタマイズ

### 環境変数

以下の環境変数でデフォルト値を上書きできる。

| 環境変数 | デフォルト値 | 説明 |
| --- | --- | --- |
| `CC_SANDBOX_PREFIX` | (空文字) | 各リソース名に付けるプレフィックス。複数環境を使い分けたい場合に設定する |
| `CC_SANDBOX_IMAGE` | `claude-code` | 使用するDockerイメージ名 |
| `CC_SANDBOX_NETWORK` | `claude-code-network` | 外部接続用Dockerネットワーク名 |
| `CC_SANDBOX_INTERNAL_NETWORK` | `claude-code-internal-network` | 内部専用Dockerネットワーク名 |
| `CC_SANDBOX_PROXY_CONTAINER` | `claude-code-proxy` | Squidプロキシコンテナ名 |
| `CC_SANDBOX_USER` | `claude` | コンテナ内のユーザー名 |
| `CC_SANDBOX_DOTCLAUDE` | `~/.claude-in-sandbox/.claude` | ホスト側の `.claude` ディレクトリのパス（認証情報や設定が保存される） |
| `CC_SANDBOX_DOTCONFIG` | `~/.claude-in-sandbox/.config` | ホスト側の `.config` ディレクトリのパス |

### アクセス許可ドメインの変更

コンテナからのHTTP/HTTPSアクセスはSquidプロキシ経由に制限されており、`proxy/whitelist.txt` に記載されたドメインのみ通信が許可される。
アクセスを許可したいドメインを追加・削除する場合はこのファイルを編集する。
Squidの `dstdomain` 形式に従い、`.example.com` と記載するとサブドメインを含むすべてのホストが対象になる。

