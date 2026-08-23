# 09: スペック全体のE2E検証

**What to build:** spec.mdのTesting Decisionsに列挙した全検証項目（マウント・ネットワーク遮断・インターネット到達・DinD/Testcontainers・code-server到達・複数インスタンス隔離・キャッシュ再利用・プロファイル注入）をWSL2/Linuxネイティブdocker環境で通しでテストし、グリーンにする。macOS実機のhost.docker.internal検証はspecのOut of Scopeの通り対象外。

**Blocked by:** 01, 02, 03, 04, 05, 06, 07, 08

**Status:** implemented-needs-verification

- [ ] `.scratch/isolated-dev-sandbox/spec.md` のTesting Decisionsに列挙された検証項目すべてが、実Dockerデーモン（WSL2/Linuxネイティブ）に対してエンドツーエンドでパスする
- [x] 一連のテストスイートが単一コマンド（または明文化された手順）として、CIでもローカルでも実行できる
- [x] macOSの`host.docker.internal`迂回検証など、既知のスコープ外事項はサイレントにスキップせず明記される

## Comments

全E2Eを単一コマンド `bin/test-e2e` で実行できるようにした。実行環境の
`docker` / `bats` / Linux Docker daemonを事前検査し、specの検証項目を構成する
全Batsファイルを実Dockerに対して実行する。ローカル・CI共通の前提条件、検証範囲、
macOS固有の`host.docker.internal`迂回検証がOut of Scopeであることは
`docs/e2e-testing.md`に明記した。

このセッションでは全45テストを起動したが、Dockerfile最初のaptレイヤーで
BuildKitはoverlay mountの`operation not permitted`、legacy builderはdpkgの
`Invalid cross-device link`となる既知のnested overlay/btrfs制約により、イメージを
ビルドできなかった。このためWSL2/Linux-native Dockerでの全項目green確認は未完了。
対応環境で `bin/test-e2e` を実行し、greenになった時点でチェックリストを完了する。
