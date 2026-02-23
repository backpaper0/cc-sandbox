# Claude Codeのコンテナイメージ

Claude Codeを安全に`--dangerously-skip-permissions`付きで動かすためのサンドボックス。

## 特徴

- Dockerコンテナに閉じ込めることで、予期せぬファイル更新・削除を防ぐ(例: `rm -fr $HOME`など)
- `internal`なDockerネットワークに閉じ込めることで、予期せぬ通信を防ぐ(例: 怪しいウェブサイトへのPOSTリクエストなど)
- bindマウントは最低限、ワークスペースとして扱うディレクトリのみ
- インターネット通信は`internal`なネットワークと`internal`でないネットワークの両方へ接続しているSquidコンテナを経由して行う
- ホスト側はVSCode等のエディタで該当ディレクトリを開いてClaude Codeが作成・編集したファイルを確認する

## インストール

このリポジトリ`git clone`する。

```bash
git clone https://github.com/backpaper0/claude-code-environment.git
```

パスが通っている場所へシンボリックリンクを作成する。

```bash
ln -s $PWD/claude-in-sandbox $HOME/.local/bin/claude-in-sandbox
```

## 起動

コマンドを実行する。

```bash
claude-in-sandbox
```

実行すると必要に応じてコンテナイメージの作成、Dockerネットワークの作成、Squidコンテナの起動などを行い、Claude Codeが動くコンテナが起動する。

