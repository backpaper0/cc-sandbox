# 04: code-server統合

**What to build:** 本体コンテナにcode-serverが同居し、`127.0.0.1`限定・パスワード認証で起動する。`up`の出力にアクセスURLとパスワードの確認方法が表示され、ブラウザでファイルツリー・Markdownプレビュー付きの編集ができる。

**Blocked by:** 01

**Status:** done

- [x] code-serverが本体コンテナに同居して動く
- [x] `127.0.0.1`にのみバインドされ、他マシン（LAN上の別端末）からは到達できない
- [x] アクセスにパスワード認証が必須になっている
- [x] `up`の出力にアクセスURLとパスワードの取得方法が表示される
- [x] ブラウザからファイルツリーとMarkdownプレビューが使える

## Comments

- 実装: `sandbox/Dockerfile`に`code-server`の公式インストールスクリプトを追加。コンテナ起動時のconfig生成（パスワード自動発行）はcode-server自身に任せ、独自のシークレット管理は持たない。`sandbox/entrypoint.sh`を新設し、`code-server --bind-addr 0.0.0.0:8080 /workspace`をバックグラウンド起動してから元のCMD（`sleep infinity`）に`exec`で引き継ぐ形にした（`ENTRYPOINT` + `CMD`)。
- `127.0.0.1`限定はコンテナ内のbind-addrではなく`sandbox/docker-compose.yml`の`ports: ["127.0.0.1::8080"]`（ホスト側IP限定＋ランダムポート）で担保している。DockerのポートフォワーディングはコンテナのブリッジIP宛にDNATするため、コンテナ内で`127.0.0.1`にバインドするとホストからの接続経路自体が成立しない。したがってコンテナ内は`0.0.0.0:8080`のまま、ホスト側の公開設定だけで「ホストのloopbackからのみ到達可能」を実現している。
- `bin/sandbox up`の出力に`docker compose port sandbox 8080`で解決した実アドレス（`http://127.0.0.1:<ランダムポート>`）と、パスワード取得コマンド（`docker exec -u dev <container> grep '^password:' ~/.config/code-server/config.yaml`）を追加。
- ファイルツリー・Markdownプレビューはcode-server（VS Code本体）の標準機能で、追加設定なしに使える想定。
- `/code-review`で4件の指摘を検出、修正済み:
  - `sandbox/entrypoint.sh`がcode-serverの起動確認をせずバックグラウンド化していたため、`up`が「起動直後でまだcode-serverがlistenしていない」「code-serverがクラッシュして存在しない」いずれの場合もサイレントに成功報告してしまう欠陥があった。`bin/sandbox`に`wait_for_code_server`（コンテナ内から`curl 127.0.0.1:8080`を最大30秒ポーリング）を追加し、ネットワーク隔離と同じfail-closedパターン（失敗時は`down`してから`exit 1`）にした。
  - `docker compose port sandbox 8080`の失敗が隔離失敗と違ってfail-closedになっておらず、コンテナが起動済み・隔離適用済みのまま`up`だけ異常終了しうる欠陥があった。同じくfail-closedの`down`&`exit 1`に揃えた。
  - `sandbox/Dockerfile`の`curl ... | sh`インストールが、ビルドに使われる`/bin/sh`（dash）にpipefailがないためcurl失敗時もパイプ全体が0で終了し、code-serverが未インストールのままビルドが成功してしまう欠陥があった。ダウンロードと実行を`&&`で明示的に分離する形に変更した。
- E2Eテスト: `test/code_server.bats`を追加（code-serverの起動確認、`up`出力のURL/パスワード取得手順の記載確認、`127.0.0.1`限定バインドの確認、未認証時はログイン画面が返ること、config.yamlのパスワードでログインでき誤ったパスワードでは弾かれること）。
- **既知の制約**: ticket 01/03と同じ理由（このエージェントの実行環境自体がoverlayfsのネストしたmountを許可しない）で、この環境内では`docker compose up --build`によるイメージビルドが実行できず、`test/code_server.bats`を実機Docker daemonに対して最後まで通すことはできなかった。代わりに`shellcheck`（`bin/sandbox`/`sandbox/entrypoint.sh`）、`docker compose config`によるYAML検証、`bats`によるテストファイル自体の構文検証（実行はビルド失敗まで到達することを確認）を行った。実機（WSL2/macOS）での`bats test/code_server.bats`実行によるフル検証は未実施のため、次回そちらでの実行を推奨する。
