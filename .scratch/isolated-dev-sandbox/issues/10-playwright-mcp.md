# 10: Playwright MCPサーバー統合

**What to build:** 本体コンテナのイメージにPlaywright MCPサーバーを焼き込み、ユーザースコープのMCP設定として全サンドボックスインスタンス共通で有効化する（プロジェクトごとの`.mcp.json`セットアップは不要）。Claude Codeがheadlessブラウザ経由で本体コンテナ上のdevサーバー(localhost)にアクセスし、スクリーンショット取得等の基本操作でWeb画面の動作確認・テストができる。ブラウザバイナリは07のキャッシュボリュームを利用し、`down`後も再ダウンロードが発生しない。

**Blocked by:** 01, 07

**Status:** ready-for-agent

- [ ] Playwright MCPサーバーが本体コンテナのイメージに含まれ、追加のプロジェクト側設定なしに全サンドボックスインスタンスで有効になっている
- [ ] Claude CodeからPlaywright MCPのツール（`browser_navigate`等）を呼び出し、本体コンテナ上で起動したdevサーバー(localhost)にheadlessブラウザからアクセスできる
- [ ] スクリーンショット取得等の基本操作が動作し、Claude Codeとの対話内で結果を確認できる
- [ ] ブラウザバイナリ(Chromium等)が07で用意した共有キャッシュボリュームに保存され、`down`後も再ダウンロードが発生しない
- [ ] 既存のネットワーク隔離ルール(ADR-0002)の範囲内で動作し、Playwright専用の追加ネットワーク設定を必要としない
