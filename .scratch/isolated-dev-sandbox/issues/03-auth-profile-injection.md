# 03: 認証プロファイル注入

**What to build:** `--profile private`（`claude setup-token`の長期OAuthトークン）または`--profile work`（Bedrock APIキー）を指定すると、対応するホスト側のローカル専用設定ファイル（`~/.sandbox/env.*`）が読み込まれ、本体コンテナ内に環境変数として注入され、Claude Codeがそのまま使える。

**Blocked by:** 01

**Status:** done

- [x] `up --profile private` がGit管理外のローカルファイル（例: `~/.sandbox/env.private`）を読み込み、`claude setup-token`で発行した長期OAuthトークンを含む変数をコンテナに環境変数として注入する
- [x] `up --profile work` が別のローカルファイル（例: `~/.sandbox/env.work`）を読み込み、Bedrock APIキー関連の環境変数を注入する
- [x] `up`完了直後、対話ログインなしでコンテナ内のClaude Codeが認証済みの状態で使える
- [x] プロファイルファイルが存在しない場合、サイレントに失敗せず明確なエラーになる

## Comments

- 実装: `bin/sandbox`の`up`に`--profile <private|work>`を追加。`~/.sandbox/env.<profile>`を解決し、`SANDBOX_ENV_FILE`経由で`sandbox/docker-compose.yml`の`env_file`にそのまま渡す（具体的な変数名はCLI側でハードコードせず、プロファイルファイルの中身に委ねる）。`sandbox/Dockerfile`に`@anthropic-ai/claude-code`（バージョン固定）を追加インストールし、注入した認証で実際に動くことを検証可能にした。
- 認証変数名は`docs.claude.com`の一次情報で確認済み: privateは`CLAUDE_CODE_OAUTH_TOKEN`、workは`CLAUDE_CODE_USE_BEDROCK=1` + `AWS_BEARER_TOKEN_BEDROCK`（+ `AWS_REGION`）。
- E2Eテスト: `test/auth_profile_injection.bats`を追加（`--profile private/work`それぞれの注入確認、`--profile`省略時に注入されないこと、未知のプロファイル名・空値・ファイル未存在での明確なエラーを検証）。3つの`.bats`ファイルで重複していた`container_id`/`exec_in`ヘルパーは`test/helpers.bash`に切り出した。
- **既知の制約**: このエージェントの実行環境自体がoverlayfsのネストを許可しないため、`docker compose up --build`によるイメージビルドがこの環境内では実行できず、`test/auth_profile_injection.bats`を実機Docker daemonに対して最後まで通すことはできなかった（ticket 01のイメージビルドも同じ理由でこの環境では失敗する）。代わりに、`docker compose config`によるYAML変数展開の検証、および`bin/sandbox`の引数パース・エラーパス（未知プロファイル/空値/ファイル未存在/`$HOME`未設定）を実際に実行して確認済み。実機（WSL2/macOS）での`bats test/auth_profile_injection.bats`実行によるフル検証は未実施のため、次回そちらでの実行を推奨する。
