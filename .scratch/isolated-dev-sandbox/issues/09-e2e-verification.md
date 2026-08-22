# 09: スペック全体のE2E検証

**What to build:** spec.mdのTesting Decisionsに列挙した全検証項目（マウント・ネットワーク遮断・インターネット到達・DinD/Testcontainers・code-server到達・複数インスタンス隔離・キャッシュ再利用・プロファイル注入）をWSL2/Linuxネイティブdocker環境で通しでテストし、グリーンにする。macOS実機のhost.docker.internal検証はspecのOut of Scopeの通り対象外。

**Blocked by:** 01, 02, 03, 04, 05, 06, 07, 08

**Status:** ready-for-agent

- [ ] `.scratch/isolated-dev-sandbox/spec.md` のTesting Decisionsに列挙された検証項目すべてが、実Dockerデーモン（WSL2/Linuxネイティブ）に対してエンドツーエンドでパスする
- [ ] 一連のテストスイートが単一コマンド（または明文化された手順）として、CIでもローカルでも実行できる
- [ ] macOSの`host.docker.internal`迂回検証など、既知のスコープ外事項はサイレントにスキップせず明記される
