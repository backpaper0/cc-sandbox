# 10: Playwright MCPサーバー統合

**What to build:** 本体コンテナのイメージにPlaywright MCPサーバーを焼き込み、ユーザースコープのMCP設定として全サンドボックスインスタンス共通で有効化する（プロジェクトごとの`.mcp.json`セットアップは不要）。Claude Codeがheadlessブラウザ経由で本体コンテナ上のdevサーバー(localhost)にアクセスし、スクリーンショット取得等の基本操作でWeb画面の動作確認・テストができる。ブラウザバイナリは07のキャッシュボリュームを利用し、`down`後も再ダウンロードが発生しない。

**Blocked by:** 01, 07

**Status:** implemented-needs-verification

- [x] Playwright MCPサーバーが本体コンテナのイメージに含まれ、追加のプロジェクト側設定なしに全サンドボックスインスタンスで有効になっている
- [ ] Claude CodeからPlaywright MCPのツール（`browser_navigate`等）を呼び出し、本体コンテナ上で起動したdevサーバー(localhost)にheadlessブラウザからアクセスできる
- [ ] スクリーンショット取得等の基本操作が動作し、Claude Codeとの対話内で結果を確認できる
- [ ] ブラウザバイナリ(Chromium等)が07で用意した共有キャッシュボリュームに保存され、`down`後も再ダウンロードが発生しないことをmacOS/WSL2実機で確認できる
- [x] 既存のネットワーク隔離ルール(ADR-0002)の範囲内で動作し、Playwright専用の追加ネットワーク設定を必要としない

## Comments

`@playwright/mcp@0.0.79`と、その依存するChromiumを本体コンテナへ焼き込んだ。Claude Codeの`user` scopeへ`playwright`として登録し、`--headless --browser chromium --no-sandbox`で起動するため、プロジェクト側の`.mcp.json`は不要。スクリーンショット等の成果物は`/tmp/playwright-mcp-output`へ出力する。

ticket 07の`/home/dev/.cache/ms-playwright`共有ボリュームをそのまま利用する。新規ボリュームはイメージ内のブラウザを初回マウント時に引き継ぎ、ticket 10以前に作成済みの空ボリュームはentrypointの`playwright install chromium`で初回だけ補完する。複数インスタンスが同時起動しても共有キャッシュへのインストールが競合しないよう`flock`で直列化した。

`test/playwright_mcp.bats`にCLI seamのE2Eテストを追加した。`up`後のuser-scope設定、MCPの公開stdio JSON-RPC経由での`browser_navigate`・`browser_take_screenshot`、`down/up`後のブラウザキャッシュ再利用を実Dockerに対して検証する。smoke clientは`claude mcp get playwright`が公開するuser-scopeのcommand/argsを取得し、その登録内容をそのまま起動するため、Dockerfile側の設定との重複・ドリフトがない。MCPプロトコル部分は同じ固定バージョンのパッケージをこの作業ホスト上で実際に起動し、localhostのfixtureへの遷移とPNG生成が成功することを確認済み。ただし、認証済みClaude Codeの対話からツールを選択・実行する結合経路は未検証。

このセッションのDocker daemonでは、既存Dockerfileの最初の`apt-get`レイヤーがBuildKitのoverlay mountで`operation not permitted`となる既知の環境制約があるため、`bin/sandbox up`を通すE2Eは実行できなかった。`docker build --check`、`docker compose config`、Bats/Pythonの構文検査、実Playwright MCPプロセスとのJSON-RPC smoke testはgreen。ターゲットのmacOS/WSL2実機で`bats test/playwright_mcp.bats`を実行するフォローアップが必要。

Playwright用のポート公開やnetwork追加は行っていない。ブラウザとdevサーバーは同じ本体コンテナ内にありlocalhostで通信するため、ADR-0004（ADR-0002をsupersede）のOUTPUT owner-match隔離にも追加例外は不要。
