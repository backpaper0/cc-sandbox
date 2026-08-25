---
Status: accepted
---

# 企業CA証明書とプロキシはホスト側ファイルの有無で自動注入し、`--profile`とは独立させる

企業ネットワークのTLS/SSL Inspection（セキュリティ監査・脅威検知・DLP目的の中間者検査）に対応するため、`~/.cc-sandbox/ca-cert.crt`（企業CA証明書、PEM1枚）と`~/.cc-sandbox/proxy.env`（`HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY`）を置き、存在すれば本体コンテナ・DinDサイドカーの両方に自動適用する方式とした。どちらも[ADR-0003](0003-auth-injection-per-host-profile.md)の認証プロファイル（`--profile`）とは独立したファイルにしている。プロキシの要否は「どの認証プロファイルを選ぶか」ではなく「どのホスト（PC）を使っているか」で決まり、同じホスト上で複数プロファイルを使い分ける場合（ticket 11）にプロキシ設定だけ重複して書く必要が出てしまうため。

Javaは例外的な対応が必要だった。mise管理のJDKは全サンドボックスインスタンス共通の永続ボリューム（`cc-sandbox-cache-mise`）に置かれるため、ビルド時に`keytool`でJDK付属の`cacerts`へ直接インポートしても、そのボリュームが一度作られた後は`docker compose build`のイメージ更新では上書きされない。そこで`cacerts`自体には手を入れず、デフォルトのCA一式に企業CA証明書を追加インポートした専用のトラストストアを`entrypoint.sh`がコンテナ起動のたびに生成し、`JAVA_TOOL_OPTIONS`の`-Djavax.net.ssl.trustStore`で参照させる方式にした。コンテナの書き込み可能レイヤーはvolumeと違って`up --build`のたびに作り直されるため、`up`側での再適用（repair）ロジックは不要になる。

curl/git/Python/npm向けの環境変数（`CURL_CA_BUNDLE`/`SSL_CERT_FILE`/`REQUESTS_CA_BUNDLE`/`PIP_CERT`/`NODE_EXTRA_CA_CERTS`等）は、企業CA証明書単体ではなく`update-ca-certificates`が生成するマージ済みの束（`/etc/ssl/certs/ca-certificates.crt`、デフォルトのCA一式＋企業CA）を指す。企業CA単体を指すと、TLS Inspection対象外の通信先でHTTPS検証が失敗するようになるため。この対応はビルド時に完結し、`up`は毎回`--build`するため実行時の再適用は不要（Javaのみが上記の理由で例外）。

プロキシの`NO_PROXY`に`dind`を除外設定する必要があるのは、`dind`サービス自身の`environment:`ではなく**本体コンテナ**（`cc-sandbox`サービス）側だと実装時に判明した。DinDサイドカーへ接続するのは本体コンテナ内で動く`docker` CLI（`DOCKER_HOST=tcp://dind:2375`）であり、`HTTP_PROXY`/`HTTPS_PROXY`が設定された状態でこのCLI自身のNO_PROXYに`dind`が含まれていないと、`tcp://dind:2375`への接続をプロキシ経由でトンネルしようとして失敗する。`dind`サービス側の`NO_PROXY`はイメージpull等の通常の対外通信にしか使わないため、`proxy.env`の値をそのまま渡せばよく、自己除外は不要。

## Considered Options

- Javaもmise管理の`cacerts`へ`keytool`で直接インポートし、`up`のたびに`ensure_playwright_browser`と同様の"repair"を行う — 動作はするが、共有ボリュームの上書き問題への対処ロジックが余分に必要になり、`entrypoint.sh`でのその場生成の方がシンプルなため見送った
- プロキシ設定を`--profile`の`env.<name>`ファイルに相乗りさせる — 新しいファイル形式を増やさずに済むが、同一ホストで複数プロファイルを使い分ける場合にプロキシ設定が重複するため見送った
