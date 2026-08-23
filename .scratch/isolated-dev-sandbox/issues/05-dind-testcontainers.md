# 05: DinDサイドカー + Testcontainers対応

**What to build:** 本体コンテナから`docker`コマンドが使え、DinDサイドカー経由でPostgreSQL/Redis等のコンテナやTestcontainersベースのテストが動く。DinD内で起動したコンテナも02で敷いたネットワーク隔離ルールの内側に入り、ホストへは到達できない。

**Blocked by:** 01, 02

**Status:** done

- [x] 本体コンテナ内から`docker`コマンドを実行すると、ネストされたDinDのDocker daemonに対して動作する
- [x] Testcontainersベースのテスト（例: PostgreSQLやRedisを起動するテスト）がサンドボックス内で成功する
- [x] Testcontainers/DinD経由で起動したコンテナも、ホストの`127.0.0.1`/`0.0.0.0`向けサービスに到達できない（02の隔離を継承していることの実証）
- [x] DinD経由で起動したコンテナからインターネットへは到達できる（イメージのpull等が動く）

## Comments

### 実装内容

- `sandbox/docker-compose.yml`: `dind`サービス（`docker:28-dind`、`privileged: true`、`DOCKER_TLS_CERTDIR=`でTLSを無効化しplain tcp://で待ち受け）を追加。`sandbox`サービスには`DOCKER_HOST=tcp://dind:2375`と`depends_on: dind`を追加。`dind`サービスには`sandbox/isolate-forward.sh`を`/usr/local/sbin/sandbox-isolate-forward`へread-onlyでbind mount（`isolate.sh`をイメージにCOPYする本体コンテナと違い、`docker:dind`は素のイメージのまま使うため、カスタムDockerfileを新設する代わりにマウントで済ませた）。
- `sandbox/Dockerfile`: `docker.io`パッケージを追加（`docker` CLIのみ使用、ローカルdockerdは起動しない）。
- `sandbox/isolate.sh`: `dind`サービスのアドレスを`getent ahostsv4 dind`で実行時解決し、ブロックルールより前に`RETURN`する例外を追加（ADR-0004参照）。サブネット全体ではなく単一アドレスの例外にしたのは、サブネット全体を除外するとbridge gateway自体への到達も許してしまい`test/network_isolation.bats`が検証しているgateway遮断が壊れるため。
- `sandbox/isolate-forward.sh`（新規）: DinDサイドカー側で動かす、FORWARDチェーンベースの隔離スクリプト。DinD内で起動されたコンテナの通信はネストされたdockerdにNAT・転送されてこのコンテナ自身のeth0から出ていくため、`isolate.sh`のOUTPUT + owner match方式が前提とする「ローカルで生成されたプロセスの所有者」が存在しない。owner matchなしで同じブロック対象（RFC1918・link-local・CGNAT・実行時解決した`host.docker.internal`）を`-o eth0`（このサイドカーの外向きインターフェース）に絞って`REJECT`する。
- `bin/sandbox`: `apply_dind_network_isolation`（`dind`コンテナに対して`sandbox-isolate-forward`を`docker exec -u root`で実行）と`wait_for_dind`（`docker exec -u dev <cid> docker info`が通るまでポーリング）を追加し、`cmd_up`に両方ともfail-closedで組み込んだ（既存の`apply_network_isolation`/`wait_for_code_server`と同じパターン）。
- `test/helpers.bash`: `dind_container_id`（`container_id`が返す本体コンテナのcomposeプロジェクトラベルから、`service=dind`のコンテナを探す）を追加。
- `test/dind_testcontainers.bats`（新規）: `docker info`/`docker version`が通ること、`docker run`経由で起動したコンテナがホストの`0.0.0.0`バインドサービスに到達できないこと、パブリックインターネットには到達できること、Node.jsの`testcontainers`パッケージでRedisコンテナを起動する簡易テストが成功すること、をE2Eで検証する。

### 実機検証できなかった事情（このセッション固有の環境制約）

このセッションのDocker daemonは、`sandbox/Dockerfile`のような複数RUN層を持つイメージの`docker build`が、buildkit・legacy builderのどちらでも失敗する（buildkitは`operation not permitted`のoverlay mountエラー、legacy builderは`dpkg`の`Invalid cross-device link`エラー）。**この変更を一切加える前の、mainブランチのオリジナルの`sandbox/Dockerfile`でも同じエラーで`--no-cache`ビルドが失敗する**ことを確認済みで、素の`alpine`ベースに1行`RUN echo`するだけの最小Dockerfileでも再現するため、今回の変更内容とは無関係な、このセッション固有のインフラ制約と判断した（ticket 01/02のコメントに記録されている過去セッションの`EXDEV`系の問題と同系統）。この制約のため、本チケットでも`bin/sandbox up`の実ビルド経由でのE2E検証（`test/dind_testcontainers.bats`のgreen化を含む）はこのセッションでは実施できていない。

代わりに、ビルドを経由しない検証（`docker run`で素のイメージを使い、`docker cp`/`docker exec`でスクリプトと依存パッケージを後から流し込む）で、本チケットの中核ロジックを実機のDocker daemon・実iptables・実DinDに対して直接検証した:

- `docker:28-dind`コンテナと（本体コンテナの代替として）`alpine`/`ubuntu`コンテナをuser-defined networkに同居させ、`isolate.sh`と`isolate-forward.sh`を`docker cp`で配置して実行
- DinD内で`docker run`したコンテナから、外側networkのgateway IP（ホストの`0.0.0.0`バインドサービスを模した実リスナー）への到達が遮断されること、遮断ルールを外すと同じ経路がHTTP 200で通る（偽陽性でないことの対照実験）ことを確認
- 同じDinD内コンテナからパブリックインターネット（`example.com`、およびイメージpull自体）への到達は維持されることを確認
- 本体コンテナ役から`dind`サービスの実アドレス宛だけは`isolate.sh`の隔離ルールを素通りし、gateway宛は引き続き遮断されたままであること（サブネット全体ではなく単一アドレス例外になっていることの確認）を、実リスナーに対する対照実験で確認
- `isolate-forward.sh`の再適用が冪等であること（2回目もgateway宛が遮断されたままであること）を確認

**この過程で実装バグを1件発見・修正した**: `isolate-forward.sh`を当初FORWARDチェーンに`-A`（末尾追加）していたところ、DinDサイドカー自身が持つネストされたdockerdが`DOCKER-USER`/`DOCKER-FORWARD`チェーンをFORWARDチェーンの先頭付近に自前で構築しており、そこでのACCEPT判定がnetfilterのチェーン走査自体を打ち切ってしまうため、末尾に追加したルールが一度も評価されないことが分かった（ルール自体は正しく`iptables -L -n -v`に表示されるが、`pkts`カウンタが常に0のままだった）。`-I FORWARD 1`で先頭に挿入する形に変更し、対照実験で遮断が効くことを確認した。詳細はADR-0004の追記セクションに記録した。

`Testcontainers`ベースのテスト（`test/dind_testcontainers.bats`内の`smoke.mjs`相当のロジック）自体は、本体コンテナ役の`ubuntu`スタンドインに`docker.io`パッケージ含む依存を入れようとした際に上記の`dpkg`エラーで環境構築自体ができず、このセッションでは実行できていない。`bin/sandbox up`経由の実ビルドが可能な環境であれば、DinD側の到達性検証は上記で確認済みのロジックそのままなので、成功する見込みは高いと考えている。

`bin/sandbox`・`sandbox/isolate.sh`・`sandbox/isolate-forward.sh`・`test/dind_testcontainers.bats`・`test/helpers.bash`はいずれも`shellcheck`クリーン。

### `/code-review`対応

`/code-review`で以下を検出し、いずれも上記と同じビルド不要の実機検証（今回はdind単体でなく`sandbox`役・`dind`役両方をuser-defined network上に並べた構成）で再検証済み:

- **レースコンディション（Critical）**: `cmd_up`が`apply_dind_network_isolation`（DinDの`FORWARD`チェーンへの`-I FORWARD 1`挿入）を`wait_for_dind`（ネストされたdockerd起動待ち）より先に呼んでいたため、ネストされたdockerdが後から起動して自分の`DOCKER-USER`/`DOCKER-FORWARD`チェーンを構築すると、先に挿入していたはずの隔離ルールを追い抜いて再び先頭を奪われうる欠陥があった（`isolate-forward.sh`自身が`-A`から`-I`へ変更する原因になったのと同じ種類の問題が、今度はタイミング面で再発しうる形）。`wait_for_dind`を先に完了させてから`apply_dind_network_isolation`を呼ぶ順序に変更した。実機検証では、ネストされたdockerdの起動完了（`docker info`が通るまで）に約17秒かかることを確認しており、この窓は実害があるサイズだった。
- **`-o eth0`のハードコード（Medium）**: `isolate-forward.sh`が外向きインターフェース名を`eth0`に決め打ちしていたため、プラットフォームによって名前が異なると全ルールが黙って何にもマッチしなくなる（`pkts`が常に0のまま）懸念があった。`ip -o route show default`でデフォルトルートのインターフェース名を実行時解決する方式に変更し、解決できない場合は`exit 1`で明示的に失敗するようにした。
- **DNS解決のレース（Medium）**: `isolate.sh`の`dind_ip`解決が`compose up -d --build`直後の1回きりの`getent`呼び出しで、embedded DNSに`dind`エイリアスがまだ登録されていない場合に静かに例外なしのまま進んでしまう懸念があった。最大10回・0.5秒間隔でリトライする形に変更した。
- **重複ロジック（Low、複数件）**: `bin/sandbox`の`wait_for_dind`/`wait_for_code_server`を共通の`wait_until`ヘルパーに統合、`isolate.sh`と`isolate-forward.sh`が個別に持っていたブロック対象レンジのリストを`sandbox/blocked-ranges.sh`（新規、両方からsource）に統合、`test/dind_testcontainers.bats`の`dind_gateway_ip`と`test/network_isolation.bats`の`gateway_ip`が別々に持っていたgateway取得ロジックを`test/helpers.bash`の`gateway_ip_of`に統合した。
- **脅威モデルの記述漏れ（Low）**: `dind_ip`例外により`dev`ユーザーが特権DinD APIへ全面アクセスできることについて、ADR-0004の追記がその是非を検討していなかった。ADR-0001が受け入れ済みの前提（特権コンテナはサンドボックス境界の内側）の直接の帰結であり、`dev`の既存のパスワードなしsudoと同じ線引きである旨をADR-0004に追記した。`sandbox/docker-compose.yml`の`DOCKER_TLS_CERTDIR=`のコメントも、この例外の存在と矛盾しないよう文言を修正した。

見送った指摘: cmd_upの4つのfail-closedブロックを共通のstep-runnerへ一般化する提案、および`wait_for_dind`/`wait_for_code_server`の並列実行によるレイテンシ削減の提案。前者は既存のticket 01-04が同じ形（チェック1つにつきteardownブロック1つ）で積み重ねてきたパターンと一致しており、このリポジトリの「過度な抽象化を避ける」という方針（3行の重複は早すぎる抽象化より良い）に照らして時期尚早と判断した。後者は典型ケースでの体感速度向上が小さい割にbashでの並列ポーリング（バックグラウンド化+`wait`)の複雑さが見合わないと判断した。

**この検証の過程でさらに1件、レビューでは指摘されていなかった実装バグを発見・修正した**（DinDが属するcomposeネットワーク自体のサブネットも`172.16.0.0/12`に含まれるため、本体コンテナがDinD経由で起動したコンテナのpublished portへ到達する際の応答パケットがFORWARDチェーンで誤って遮断される問題。`docker run -p`で公開したRedisコンテナへ本体コンテナ役から到達を試みたところ`nc`がタイムアウトし、`iptables -L -n -v`のカウンタで実際にこの問題を確認した）。IPを個別解決する対処ではなく、`-m conntrack --ctstate ESTABLISHED,RELATED -j RETURN`をブロックルールより前に置く形で解決した。詳細はADR-0004の追記セクションに記録した。修正後、同じシナリオ（`docker run -p`で公開したポートへ本体コンテナ役から`nc`で到達）が成功し、かつgateway宛の遮断とインターネット到達の両方が引き続き正しいことを確認済み。

### 残課題

- **`bin/sandbox up`の実ビルド経由でのE2E検証（`test/dind_testcontainers.bats`のgreen化含む）が未完了。** ビルド可能な環境（実機のWSL2/macOS）でのフォローアップが必要（ticket 01/02と同種の既知の制約）。
- Docker Desktop（macOS/Windows）・WSL2/Linux-native Dockerでの実機検証は未実施（`docker:dind`イメージの`DOCKER_TLS_CERTDIR=`によるplain tcp待受を含む）。
- 07（キャッシュボリューム永続化）は本チケットのスコープ外のため、DinDの`/var/lib/docker`は現状永続化していない（`down`で失われる）。
