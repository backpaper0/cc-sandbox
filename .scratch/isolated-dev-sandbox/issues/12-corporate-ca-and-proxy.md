# 12: 企業CA証明書・プロキシへの対応（TLS/SSL Inspection）

**What to build:** 企業ネットワークのTLS/SSL Inspection（セキュリティ監査・脅威検知・DLP目的の中間者検査）に対応する。ホスト側に置いた企業CA証明書とプロキシ設定を、コンテナビルド時・実行時の両方で、本体コンテナ・DinDサイドカーの両方に自動適用する。詳細な設計判断は[ADR-0007](../../../docs/adr/0007-corporate-ca-and-proxy-per-host-file.md)を参照。

**Status:** todo

- [ ] `sandbox/Dockerfile`: ビルドコンテキスト内に置かれた企業CA証明書ファイルを`/usr/local/share/ca-certificates/`へ配置し、`update-ca-certificates`で`/etc/ssl/certs/ca-certificates.crt`（デフォルトCA一式＋企業CAのマージ済み束）に取り込む。ファイルが空/存在しない場合はno-opにする
- [ ] `bin/cc-sandbox`: `up`のたびに`~/.cc-sandbox/ca-cert.crt`（存在すれば）をビルドコンテキスト内の固定パス（`.gitignore`対象）へコピーしてから`compose build`を呼ぶ
- [ ] `bin/cc-sandbox`: `~/.cc-sandbox/proxy.env`（存在すれば）を読み込み、`HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY`を自身のシェル環境にexportしてから`compose build`/`compose up`を呼ぶ（BuildKitの自動プロキシ伝播と、`docker-compose.yml`の`dind`サービスの`environment:`展開の両方に使う）
- [ ] `docker-compose.yml`: `cc-sandbox`サービスの`env_file`に`${CC_SANDBOX_PROXY_ENV_FILE:-/dev/null}`を追加し、`proxy.env`を実行時にも注入する。`dind`サービスの`environment:`に`HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY`を渡す（`NO_PROXY`には`dind`自身のアドレス等、内部通信を除外する値を含める）
- [ ] `sandbox/entrypoint.sh`: コンテナ起動のたびに、mise管理JDKのデフォルト`cacerts`をコピーして企業CA証明書を追加インポートした専用トラストストアを生成し、`JAVA_TOOL_OPTIONS`で`-Djavax.net.ssl.trustStore`/`-Djavax.net.ssl.trustStorePassword`を設定する。証明書が無ければno-opにする
- [ ] `bin/cc-sandbox`: `apply_network_isolation`と同様のパターンで、`up`のたびにDinDサイドカーへ`docker exec -u root`で企業CA証明書をインストールする処理（Alpineの`update-ca-certificates`）を追加する
- [ ] `.gitignore`: ビルドコンテキストへコピーする証明書の一時ファイルパスを除外する
- [ ] README・usage文言を更新し、`~/.cc-sandbox/ca-cert.crt`・`~/.cc-sandbox/proxy.env`の置き方を説明する
- [ ] E2Eテスト（新規）で、証明書ファイルがある場合/ない場合の両方の挙動を検証する
