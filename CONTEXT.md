# cc-sandbox

Claude Code を bypass permissions モードで安全に動かすため、ホスト（macOS / WSL2）から隔離された使い捨ての開発環境を一発コマンドで構築・破棄するための仕組み。

## Language

**cc-sandbox**:
このリポジトリが提供するツールそのものの名前（CLI・イメージ定義・関連スクリプト一式）。サンドボックス（後述）を一発コマンドで構築・破棄する主体を指す。
_Avoid_: このツール, 本ツール（曖昧なので固有名詞のcc-sandboxを使う）。サンドボックスとは区別する（cc-sandboxは「構築する側」、サンドボックスは「構築される側」）

**サンドボックス**:
Claude Code と mise/uv/Python/Java/Node.js/Docker/Vim/code-server/Playwright MCPサーバー 一式を含む、ホストから隔離された使い捨ての開発ワークスペース（本体コンテナ + DinDサイドカー等のコンテナ群一式）の設計・構成そのものを指す。cc-sandbox（前述）が構築・破棄する対象であり、ツール自体の名前ではない。
_Avoid_: 環境, コンテナ（単体を指すには曖昧）

**Playwright MCPサーバー**:
本体コンテナのイメージに焼き込まれ、全サンドボックスインスタンス共通でユーザースコープ有効化されるMCPサーバー。Claude Codeがheadlessブラウザを操作し、本体コンテナ上で動くdevサーバー等のWeb画面の動作確認・検証に使う。ライブ目視（VNC等）は提供せず、スナップショット/スクリーンショットによる事後確認のみ。
_Avoid_: ブラウザ自動化, E2Eテストツール（Playwright MCPサーバーに統一する）

**サンドボックスインスタンス**:
特定のプロジェクト用に起動された、サンドボックス一式（本体コンテナ・DinDサイドカー・専用network・専用volume）の実行単位。他のインスタンスとは相互に隔離される。
_Avoid_: セッション, ワークスペース

**本体コンテナ**:
サンドボックスインスタンスの中心となるコンテナ。Claude Code・開発ツール一式・code-serverが動き、非rootユーザーを起点にsudoが無制限で使える。
_Avoid_: メインコンテナ, アプリコンテナ

**claudeラッパー**:
本体コンテナ内で `claude` という名前で PATH 上の実バイナリより手前に置かれる薄いラッパースクリプト。引数なしの素のセッション起動には `--dangerously-skip-permissions --permission-mode bypassPermissions` を自動付与し、既知のトップレベルサブコマンド呼び出しや、ユーザーが権限系フラグを明示した呼び出しには何も足さずそのまま実バイナリへ渡す。
_Avoid_: alias, シェル関数（PATHシャドーイング方式を採用したため、この2つとは区別する）

**DinDサイドカー**:
本体コンテナに併走する特権コンテナで、ネストしたDocker daemonを提供する。Testcontainersや、開発者が手動で起動するPostgreSQL/Redis等のサービスコンテナはここで動く。本体コンテナと同じネットワーク隔離ルールの内側に置かれる。
_Avoid_: ネストDocker, Docker-in-Docker（説明文中ではこの一般名称を使ってよいが、用語としてはDinDサイドカーに統一する）

**ホスト**:
サンドボックスの外側にある、macOS（私的環境）またはWSL2 Ubuntu（業務環境）上の物理/仮想マシン。サンドボックスインスタンスから隔離される対象。
_Avoid_: ローカル環境, マシン

**`~/.cc-sandbox`**:
ホスト側にある、cc-sandboxのローカル状態を置くディレクトリ（Git管理外）。認証プロファイル（`env.<name>`、[ADR-0003](docs/adr/0003-auth-injection-per-host-profile.md)）と、`install.sh`がcloneするリポジトリ本体（`src/`）の両方をこの下に置く。
_Avoid_: 設定ディレクトリ（何の設定か曖昧なので`~/.cc-sandbox`と明示する）

**install.sh**:
`curl -fsSL <URL> | bash`で取得・実行する、cc-sandboxのインストールスクリプト。リポジトリを`~/.cc-sandbox/src`にclone（既にあれば更新）し、`bin/cc-sandbox`を`~/.local/bin`へsymlinkすることで、どのディレクトリからでも`cc-sandbox`コマンドを呼べるようにする（[ADR-0005](docs/adr/0005-install-script-fixed-clone-and-symlink.md)）。
_Avoid_: セットアップスクリプト, インストーラ（固有名詞のinstall.shで統一する）
