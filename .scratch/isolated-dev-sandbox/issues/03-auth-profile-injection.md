# 03: 認証プロファイル注入

**What to build:** `--profile private`（`claude setup-token`の長期OAuthトークン）または`--profile work`（Bedrock APIキー）を指定すると、対応するホスト側のローカル専用設定ファイル（`~/.sandbox/env.*`）が読み込まれ、本体コンテナ内に環境変数として注入され、Claude Codeがそのまま使える。

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] `up --profile private` がGit管理外のローカルファイル（例: `~/.sandbox/env.private`）を読み込み、`claude setup-token`で発行した長期OAuthトークンを含む変数をコンテナに環境変数として注入する
- [ ] `up --profile work` が別のローカルファイル（例: `~/.sandbox/env.work`）を読み込み、Bedrock APIキー関連の環境変数を注入する
- [ ] `up`完了直後、対話ログインなしでコンテナ内のClaude Codeが認証済みの状態で使える
- [ ] プロファイルファイルが存在しない場合、サイレントに失敗せず明確なエラーになる
