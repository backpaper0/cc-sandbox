# 12: 企業CA証明書・プロキシへの対応（TLS/SSL Inspection）

**What to build:** 企業ネットワークのTLS/SSL Inspection（セキュリティ監査・脅威検知・DLP目的の中間者検査）に対応する。ホスト側に置いた企業CA証明書とプロキシ設定を、コンテナビルド時・実行時の両方で、本体コンテナ・DinDサイドカーの両方に自動適用する。詳細な設計判断は[ADR-0007](../../../docs/adr/0007-corporate-ca-and-proxy-per-host-file.md)を参照。

**Status:** implemented-needs-verification

- [x] `sandbox/Dockerfile`: ビルドコンテキスト内に置かれた企業CA証明書ファイルを`/usr/local/share/ca-certificates/`へ配置し、`update-ca-certificates`で`/etc/ssl/certs/ca-certificates.crt`（デフォルトCA一式＋企業CAのマージ済み束）に取り込む。ファイルが空/存在しない場合はno-opにする。加えて`CURL_CA_BUNDLE`/`SSL_CERT_FILE`/`REQUESTS_CA_BUNDLE`/`PIP_CERT`/`NODE_EXTRA_CA_CERTS`をそのマージ済み束に向けて設定（Node/pipは独自CAバンドルを使いOSのトラストストアを見ないため、`update-ca-certificates`だけでは不十分——最初の実装ではこれが抜けており、レビューで発覚）
- [x] `bin/cc-sandbox`: `up`のたびに`~/.cc-sandbox/ca-cert.crt`（存在すれば）をビルドコンテキスト内の固定パス（`.gitignore`対象）へコピーしてから`compose build`を呼ぶ。このパスは全インスタンス共通のため、`--name`で複数インスタンスを同時起動した場合のステージング競合をレビューで指摘され、専用ロック（`acquire_lock "ca-cert-build"`）で直列化した
- [x] `bin/cc-sandbox`: `~/.cc-sandbox/proxy.env`（存在すれば）を読み込み、`HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY`を自身のシェル環境にexportしてから`compose build`/`compose up`を呼ぶ（BuildKitの自動プロキシ伝播と、`docker-compose.yml`の`dind`サービスの`environment:`展開の両方に使う）
- [x] `docker-compose.yml`: `cc-sandbox`サービスの`env_file`に`${CC_SANDBOX_PROXY_ENV_FILE:-/dev/null}`を追加し、`proxy.env`を実行時にも注入する。`dind`サービスの`environment:`にも`HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY`を渡す。`NO_PROXY`の`dind`除外は、実装時のレビューで判明した通り`dind`側ではなく`cc-sandbox`サービス側の`environment:`で`env_file`の値を上書きする形で実施（`tcp://dind:2375`へ接続するdocker CLIは本体コンテナ側で動くため。詳細はADR-0007）
- [x] `sandbox/entrypoint.sh`: コンテナ起動のたびに、mise管理JDKのデフォルト`cacerts`をコピーして企業CA証明書を追加インポートした専用トラストストアを生成し、`JAVA_TOOL_OPTIONS`で`-Djavax.net.ssl.trustStore`/`-Djavax.net.ssl.trustStorePassword`を設定する。証明書が無ければno-opにする
- [x] `bin/cc-sandbox`: `apply_network_isolation`と同様のパターンで、`up`のたびにDinDサイドカーへ`docker exec -u root`で企業CA証明書をインストールする処理（Alpineの`update-ca-certificates`）を追加する
- [x] `.gitignore`: ビルドコンテキストへコピーする証明書の一時ファイルパスを除外する
- [x] README・usage文言を更新し、`~/.cc-sandbox/ca-cert.crt`・`~/.cc-sandbox/proxy.env`の置き方を説明する
- [ ] E2Eテスト（新規、`test/corporate_ca_and_proxy.bats`）で、証明書ファイルがある場合/ない場合の両方の挙動を検証する — テストコード自体は書いたが、この環境では未実行（下記コメント参照）

## Comments

この実装エージェントの実行環境自体が、BuildKitのoverlayfsマウントを許可しないネストされたコンテナ環境だったため、`bin/test-e2e`（および既存の`test/basic_up_down.bats`含む全E2Eスイート）が`docker compose build`の時点で失敗する（`mount source: "overlay", ... err: operation not permitted`）。変更前のmainブランチに戻しても同じエラーが再現することを確認済みで、この失敗はticket 12の変更が原因ではなく環境側の制約。

そのためこの環境では以下のみ実施した:
- `bash -n`によるbin/cc-sandbox・sandbox/entrypoint.shの構文チェック
- `docker compose -f sandbox/docker-compose.yml config`によるcompose定義の解決確認（新しい変数・バインドマウントが期待通り展開されることを確認）
- `bin/cc-sandbox`から`stage_ca_certificate`/`load_proxy_env`/`acquire_lock`を抽出した簡易ハーネスによる単体的な動作確認（証明書ファイルのステージング／削除、`HTTP_PROXY`等の読み込み、`CC_SANDBOX_NO_PROXY`の組み立て、複数ロックが単一EXITトラップの下で正しく解放されることを確認）
- `/code-review`（フォークで並行実行）で4件の指摘を受け、うち以下3件を修正: (1) `NO_PROXY`の`dind`除外が`dind`サービス側についていたが、実際に`tcp://dind:2375`へダイヤルするのは本体コンテナ側の`docker` CLIなので`cc-sandbox`サービス側の`environment:`で上書きする形に修正、(2) `CA_CERT_DEST`が全インスタンス共通の単一パスなのに複数インスタンス同時起動時の排他制御が無かったので専用ロックを追加、(3) Node/pipが独自CAバンドルを使いOSトラストストアを見ない問題を`NODE_EXTRA_CA_CERTS`等の追加で解消。4件目（`docker restart`時の`~/.bashrc`重複追記）は軽微だが併せてgrepガードで冪等化した

実際のイメージビルド・コンテナ起動を伴う検証（Dockerfileのcert COPY、entrypoint.shのkeytool処理、DinDサイドカーへの`update-ca-certificates`適用、`test/corporate_ca_and_proxy.bats`の実行）は、privileged/overlayfsが使えるWSL2または Linux ネイティブのDocker環境で`bin/test-e2e`を実行して確認する必要がある。
