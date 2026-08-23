# アーキテクチャ決定記録（ADR）

| # | タイトル | ステータス | 日付 |
| :--- | :--- | :--- | :--- |
| [0001](0001-dind-sidecar-privileged.md) | DinDサイドカーは特権コンテナ方式で実装する | accepted | 2026-08-23 |
| [0002](0002-network-isolation-docker-user-iptables.md) | ネットワーク隔離はデフォルトbridge + DOCKER-USER iptablesルールの多層防御とする | superseded by ADR-0004 | 2026-08-23 |
| [0003](0003-auth-injection-per-host-profile.md) | Claude Code認証はホストごとのローカル設定ファイルから環境変数として注入する | accepted | 2026-08-23 |
| [0004](0004-network-isolation-in-container-owner-match.md) | ネットワーク隔離はサンドボックス内のiptables + owner matchで非rootユーザーのみを遮断する | accepted | 2026-08-23 |
