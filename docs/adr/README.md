# アーキテクチャ決定記録（ADR）

| # | タイトル | ステータス | 日付 |
| :--- | :--- | :--- | :--- |
| [0001](0001-dind-sidecar-privileged.md) | DinDサイドカーは特権コンテナ方式で実装する | accepted | 2026-08-23 |
| [0002](0002-network-isolation-docker-user-iptables.md) | ネットワーク隔離はデフォルトbridge + DOCKER-USER iptablesルールの多層防御とする | superseded by ADR-0004 | 2026-08-23 |
| [0003](0003-auth-injection-per-host-profile.md) | Claude Code認証はホストごとのローカル設定ファイルから環境変数として注入する | accepted | 2026-08-23 |
| [0004](0004-network-isolation-in-container-owner-match.md) | ネットワーク隔離はサンドボックス内のiptables + owner matchで非rootユーザーのみを遮断する | accepted | 2026-08-23 |
| [0005](0005-install-script-fixed-clone-and-symlink.md) | インストールはリポジトリを`~/.cc-sandbox/src`にcloneし、`bin/cc-sandbox`を`~/.local/bin`へsymlinkする方式とする | accepted | 2026-08-25 |
| [0006](0006-interactive-profile-selection.md) | `--profile`に値を省略すると、既存プロファイルから対話的に選択できるようにする | accepted | 2026-08-25 |
| [0007](0007-corporate-ca-and-proxy-per-host-file.md) | 企業CA証明書とプロキシはホスト側ファイルの有無で自動注入し、`--profile`とは独立させる | accepted | 2026-08-25 |
| [0008](0008-restrict-dev-sudo-to-package-management.md) | `dev`のsudoはOSパッケージ管理コマンドのみに限定する | accepted | 2026-08-26 |
| [0009](0009-turn-notification-via-host-watcher.md) | ユーザー入力ターンの通知は、ホスト常駐の「通知ウォッチャー」が`Stop`/`idle_prompt`フックを検知する方式とする | accepted | 2026-08-26 |
| [0010](0010-profile-selection-via-environment-variable.md) | `--profile`の自動選択は`CC_SANDBOX_PROFILE`環境変数を読む方式とし、cc-sandbox自身はディレクトリツリー探索を持たない | accepted | 2026-08-27 |
| [0011](0011-help-and-docs-in-japanese.md) | ヘルプ・ユーザー向けドキュメントは英語ではなく日本語で統一する | accepted | 2026-08-27 |
