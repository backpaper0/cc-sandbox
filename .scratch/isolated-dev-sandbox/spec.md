# Isolated Dev Sandbox

Status: ready-for-agent

## Problem Statement

Claude Codeをbypass permissionsモードで使うと、コマンド実行やファイル削除が確認なしに実行されるため、誤操作や意図しない副作用がホスト環境（macOSの私的環境、WSL2 Ubuntuの業務環境）に及ぶリスクがある。現状ではこのリスクを引き受けてホスト上で直接bypass permissionsを使うか、確認プロンプトを都度挟んで利便性を犠牲にするかの二択になっている。

## Solution

ホストから隔離された使い捨ての開発環境（サンドボックス）を一発コマンドで構築・破棄できるようにする。サンドボックスインスタンス内でClaude Codeをbypass permissionsモードで動かしても、ホストのファイルシステムやネットワークサービスに意図せず影響が及ばないようにしつつ、mise/uv/Python/Java/Node.js/Docker/Vim/code-serverが使える開発体験を維持する。

## User Stories

1. As a developer running Claude Code on macOS, I want to spin up an isolated sandbox with one command, so that I can let Claude Code run in bypass permissions mode without confirming every action.
2. As a developer running Claude Code on WSL2 (Ubuntu), I want the same one-command provisioning to work identically to the macOS version, so that I don't need to learn two different workflows.
3. As a developer, I want to specify which host project directory gets mounted into the sandbox, so that Claude Code can read and write my project's files.
4. As a developer, I want secrets like `~/.ssh` and `~/.aws` to never be exposed inside the mounted directory, so that a compromised or overly permissive sandbox process can't exfiltrate my credentials.
5. As a developer, I want the sandbox to be unable to reach services listening on the host, so that a runaway command inside the sandbox can't touch my other local projects' databases or dev servers.
6. As a developer, I want the sandbox to still have outbound internet access, so that package installs and API calls Claude Code needs to make still work.
7. As a developer, I want the block on reaching host services to hold even if I forget to bind a host dev server to loopback only, so that isolation doesn't silently depend on me remembering an operational rule.
8. As a developer, I want the sandbox to expose code-server so I can browse/edit files with a richer UI (file tree, Markdown preview), so that I'm not limited to a terminal-only editing experience for these tasks.
9. As a developer, I want Vim available in the sandbox terminal, so that I retain my primary editing muscle memory.
10. As a developer, I want code-server to require a password and be reachable only from localhost, so that I'm not accidentally exposing an editor with full filesystem access to my LAN.
11. As a developer, I want to run PostgreSQL, Redis, or other service containers inside the sandbox, so that I can develop and test against realistic dependencies.
12. As a developer, I want to use Testcontainers inside the sandbox, so that my test suite's existing Testcontainers-based tests keep working unmodified.
13. As a developer, I want the nested Docker environment (DinDサイドカー) to be subject to the same network isolation rules as the本体コンテナ, so that a container started via Testcontainers can't become a backdoor to the host.
14. As a developer, I want to run multiple sandbox instances at the same time (e.g. for different projects), so that I can work on more than one thing in parallel.
15. As a developer, I want each sandbox instance to be isolated from other instances (separate network, separate volumes), so that a mistake in one project's sandbox can't affect another project's sandbox.
16. As a developer, I want to tear down and recreate a sandbox instance quickly, so that I can treat it as disposable without losing significant setup time.
17. As a developer, I want tool caches (mise, uv, npm, Maven, Docker image layers) to persist across sandbox recreation, so that rebuilding a sandbox doesn't mean re-downloading everything from scratch.
18. As a developer, I want the tool caches to be shared across all sandbox instances, so that provisioning a new instance benefits from work already done by other instances.
19. As a developer, I want to operate as a non-root user inside the sandbox by default, with unrestricted sudo available, so that accidental destructive commands aren't automatically running as root, while still being able to install packages freely when needed.
20. As a private-use (macOS) developer using a Claude subscription, I want the sandbox's Claude Code authenticated with a long-lived OAuth token generated once via `claude setup-token`, so that I don't need to interactively log in every time I recreate a disposable sandbox.
21. As a work (WSL2) developer using Amazon Bedrock, I want the sandbox's Claude Code authenticated with my Bedrock API key, so that the sandbox works with my company's model access setup.
22. As a developer, I want each host machine to keep its own local, git-ignored auth profile file, so that I don't have to pass auth secrets manually every time I provision a sandbox.
23. As a developer, I want the provisioning CLI to accept a project directory and a profile/instance name and handle everything else, so that spinning up a new sandbox is a single, memorable command.
24. As a developer, I want to list currently running sandbox instances, so that I can see what's active before starting a new one or tearing one down.
25. As a developer, I want the sandbox-to-host network block to be verified at least on the WSL2/Linux-native Docker case, so that I have a documented, testable baseline, with macOS-specific verification tracked as a known follow-up.
26. As a developer, I want a Playwright MCP server available in the sandbox out of the box, so that Claude Code can drive a headless browser against my project's dev server to verify and test web UI behavior without any per-project setup.

## Implementation Decisions

- **CLIエントリポイント（唯一のseam）**: `bin/sandbox`。サブコマンドは `up <project-dir> --profile <name> [--name <slug>]` / `down <slug>` / `list`。ライフサイクル操作は全てこのCLIを通す。内部実装（iptablesルール適用、compose生成、環境変数注入）は個別にテストせず、このCLIを通したE2Eテストに寄せる。
- **コンテナ構成**: サンドボックスインスタンスごとに `docker compose -p <slug>` で以下を起動する。
  - **本体コンテナ**: Claude Code、mise/uv/Python/Java/Node.js/Vim/code-serverが動く。非rootユーザーを起点に、パスワードなしの無制限sudoを許可する。
  - **DinDサイドカー**: `docker:dind` の特権コンテナ（ADR-0001）。本体コンテナからは `DOCKER_HOST` 環境変数でDinDのソケットを指す。Testcontainers由来のコンテナもこのDinD内、同じネットワークに乗る。
- **ディスク**: ホストのプロジェクトディレクトリ1つを本体コンテナにbind mountする（1インスタンス=1プロジェクト）。`~/.ssh`・`~/.aws`等の機密はマウント対象に含めない運用とし、CLI側での除外機構は設けない（運用ルールに委ねる）。
- **ネットワーク**（ADR-0002）: インスタンスごとに専用のuser-defined bridgeネットワークを作成する。`up`実行時に `DOCKER-USER` iptablesチェーンへ、そのネットワークのサブネットからホストのプライベートIP帯（RFC1918）への到達をDROPするルールを追加し、`down`時に除去する。`--internal`は使わずインターネットアクセスは許可のままにする。macOS側での`host.docker.internal`迂回リスクは本スペックでは未検証のまま進める（Out of Scope）。
- **インスタンス分離**: 各インスタンスは専用のDocker network・専用のプロジェクト用bind mountを持つ。ポートは固定せずDockerにランダム割当させ、`up`の出力で確認できるようにする。
- **キャッシュ永続化**: mise/uv/npm/Maven(`~/.m2`)/Dockerイメージレイヤー/Playwrightブラウザバイナリ用に、全インスタンス共通の名前付きボリュームを用意し、本体コンテナ・DinDサイドカーにマウントする。`down`ではこれらのボリュームを削除しない。
- **code-server**: 本体コンテナに同居させる。`127.0.0.1`にのみバインドし、パスワード認証を有効にする。`up`はアクセスURLとパスワードの取得方法を出力する。
- **認証プロファイル**（ADR-0003、ticket 11で`private`/`work`固定の2択から任意名に拡張）: ホストごとにローカル専用の設定ファイル（Git管理外、例 `~/.sandbox/env.private` / `~/.sandbox/env.work`）を用意し、`--profile <name>`で読み込む対象を切り替える。`<name>`は英数字・`-`・`_`からなる任意の文字列で、固定の2値には限定されない（案件・クライアントごとにプロファイルを分けられる）。`private`プロファイルは`claude setup-token`で発行した長期OAuthトークンを、`work`プロファイルはAmazon BedrockのAPIキー関連の環境変数を保持する、という運用例は変わらない。CLIはこのファイルを読み込み本体コンテナへ環境変数として注入する。`~/.claude/.credentials.json`の直接マウントは行わない。
- **Playwright MCPサーバー**: 本体コンテナのイメージにPlaywright MCPサーバーを焼き込み、ユーザースコープのMCP設定として全サンドボックスインスタンス共通で有効化する（プロジェクトごとの`.mcp.json`には依存しない）。headlessモードで動作し、本体コンテナ上でdeveloperが起動するdevサーバー(localhost)を主な検証対象とする。VNC等によるライブ目視は提供せず、Claude Codeが取得するスクリーンショット/スナップショットを対話内で確認する運用とする。ブラウザバイナリ(Chromium等)はキャッシュ永続化用の共有ボリュームに保存する。

## Testing Decisions

- **良いテストの基準**: CLIの内部実装（iptablesコマンドの組み立て、compose YAML生成ロジックなど）ではなく、CLIを実際に呼び出した結果として外部から観測できる振る舞いだけを検証する。
- **テスト対象**: `bin/sandbox up` / `down` / `list` の3コマンドをE2Eで検証する。実際のDockerデーモンに対して実行し、モックはしない。
- **検証項目**（合意済みseamに基づく）:
  - プロジェクトディレクトリが本体コンテナ内に想定パスでマウントされること
  - 本体コンテナからホストの`127.0.0.1`向けサービス・`0.0.0.0`向けサービスのいずれにも到達できないこと
  - 本体コンテナからインターネットへは到達できること
  - DinD経由で`docker run`が動作し、Testcontainersの簡単なテストが成功すること
  - code-serverが`127.0.0.1`の割り当てポートでパスワード認証付きに到達可能であること
  - 2つのインスタンスを同時に起動し、互いのネットワーク・ボリュームが分離されている（相互到達不可）こと
  - `down`後もキャッシュ用の名前付きボリュームが残り、再度`up`した際に再利用されること
  - `--profile private` / `--profile work` それぞれで、対応する環境変数が本体コンテナ内に注入されていること（`private`/`work`以外の任意名のプロファイルでも同様に注入されること）
  - Playwright MCPサーバー経由で、本体コンテナ上のdevサーバーにheadlessブラウザからアクセスし、スクリーンショット取得等の基本操作が動作すること
- **先行事例**: このリポジトリにはまだテストコードが存在しない。E2Eテストはシェルベースの統合テスト（bats等）として新規に書く想定。

## Out of Scope

- macOS（OrbStack/Docker Desktop）側での`host.docker.internal`迂回経路の実機検証（既知の残課題、別途issue化する）
- sysbox/rootless Dockerへの移行（ADR-0001で見送り済み）
- `--internal`ネットワーク＋egressプロキシ方式への切り替え（ADR-0002で見送り済み）
- code-server向けのVimキーバインド拡張の導入
- サンドボックスの監視・ロギング基盤
- CI/CDとの統合

## Further Notes

- 本スペックの前提となる用語・決定は `CONTEXT.md` および `docs/adr/0001-dind-sidecar-privileged.md` / `docs/adr/0002-network-isolation-docker-user-iptables.md` / `docs/adr/0003-auth-injection-per-host-profile.md` に記録済み。実装時はこれらを踏襲すること。
- 完了条件にはWSL2実機・macOS実機の両方での動作検証を含める。
