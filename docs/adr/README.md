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
