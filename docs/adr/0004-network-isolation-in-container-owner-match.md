---
status: "accepted"
date: 2026-08-23
decision-makers: [Uragami Taichi]
consulted: []
informed: []
---

# ネットワーク隔離はサンドボックス内のiptables + owner matchで非rootユーザーのみを遮断する

## 背景と課題

[ADR-0002](0002-network-isolation-docker-user-iptables.md) は、ホスト側の `DOCKER-USER` チェーン（実装時に `INPUT` チェーンも追加）へiptablesルールを投入する方式を決めていた。この方式には ADR-0002 の時点で「macOS側でOrbStack/Docker Desktopの`host.docker.internal`がこのルールを迂回しないかは未検証」という留保が付いていた。

ticket 02 のフォローアップとしてmacOS実機（OrbStack）で検証したところ、この方式が前提としていた条件が2つとも崩れていることが分かった。

1. **ホストにiptablesが存在しない。** macOSではDocker daemonがOrbStackのLinux VM内で動くため、ホスト側から`iptables`を実行できない。結果として`bin/sandbox up`はネットワーク隔離の適用に必ず失敗し、fail-closed設計に従ってコンテナを破棄して`exit 1`する。ticket 01 で通っていた `test/basic_up_down.bats` が6件中5件失敗する状態になっていた。specのUser Story 1・Problem StatementはいずれもmacOSを第一級のターゲットとしているため、macOSで`up`が成立しない方式は採用できない。
2. **RFC1918宛のルールでは迂回経路を塞げない。** OrbStackでは`host.docker.internal`が`0.250.250.254`に解決される。これはRFC1918の範囲外であり、ADR-0002 が想定していたRFC1918宛DROPルールでは（仮にVM内で実行したとしても）カバーできない。実測では、ルールなしの状態でコンテナからホストの`0.0.0.0`バインドサービスへこの経路でHTTP 200が返った。ADR-0002 が未検証としていた迂回リスクは実在した。

ネットワーク隔離をどの層で実施すべきかを決め直す必要がある。

## 決定要因

* macOS（OrbStack/Docker Desktop）とWSL2/Linux-native Dockerの両方で、同一のコードパスで動くこと（spec User Story 1・2）
* ホストの`0.0.0.0`バインドサービスへの到達を、運用ルールに依存せず塞げること（spec User Story 5・7）
* インターネットへの到達とDNS解決が維持されること（spec User Story 6）
* E2Eテストが対話的な入力なしに自動実行できること（ホスト側`sudo`のパスワード入力はbatsの実行を止める）
* 防ぐ対象は「bypass permissionsモードでの誤操作や意図しない副作用」であって、サンドボックス内からの意図的な脱出ではない（spec Problem Statement）

## 検討した選択肢

* 選択肢A: サンドボックス本体コンテナ内のiptables `OUTPUT` チェーン + owner match（`--uid-owner`）で非rootユーザーのみを遮断する
* 選択肢B: ホスト種別を判定し、macOSではVM内で特権コンテナ経由でiptablesを実行する（ADR-0002 の方式をmacOSへ拡張する）
* 選択肢C: 現状維持（ADR-0002 の方式のまま、macOSでは隔離不可を検出して警告を出しつつ`up`を続行する fail-open）

## 決定

**採用: 選択肢A**

コンテナの内側にルールを置くことで、ホスト側にiptablesが存在するかどうかという最大の環境差が決定要因から消える。macOSでもLinuxでも`docker exec -u root`でルールを適用する同一の手順で済み、ホスト側の`sudo`も不要になるため、E2Eテストの自動実行という要因も同時に満たせる。迂回経路については、`host.docker.internal`を実行時に解決してブロック対象に加えることで、RFC1918の外に置かれるOrbStack/Docker Desktopの経路もカバーする。

選択肢Aは「rootは隔離できない」という弱点を持つ。サンドボックス内の`dev`ユーザーはパスワードなしsudoを持つ（spec User Story 19）ため、`sudo iptables -F`でルールを外せる。これは意図的な脱出を防げないことを意味するが、本specが防ぎたいのは誤操作と意図しない副作用であり、この線引きは要因の最後の項目に照らして許容できると判断した。この許容はユーザーの明示的な判断による。

なお、選択肢Aへの変更は隔離の適用範囲をむしろ広げている。ADR-0002 の方式はサンドボックスのサブネット全体を対象としていたが、選択肢Aは非rootユーザーのプロセスに限定される一方で、ブロック対象の宛先にlink-local（`169.254.0.0/16`）とCGNAT（`100.64.0.0/10`）、および実行時解決した`host.docker.internal`を加えている。

### 結果として生じること

* 良い点: macOSとLinuxで分岐のない単一の実装になり、ホスト側の`sudo`・iptablesへの依存が消える。`bin/sandbox`からホスト側ルールの投入・除去・冪等化のロジックが丸ごと不要になった。
* 良い点: `down`でルールを除去する処理が要らない。ルールはコンテナと寿命を共にするため、ホストに残留物が原理的に生じない。ホストのファイアウォール設定を一切変更しない。
* 良い点: E2Eテストがsudoなしで完走する。`test/network_isolation.bats` がmacOS実機で8/8 greenになった。
* 悪い点: rootを隔離できない。`dev`ユーザーはsudo経由でルールを削除できるため、意図的な回避に対する防御にはならない。
* 悪い点: `NET_ADMIN` capabilityを本体コンテナに付与する必要がある。サンドボックス内のプロセスがコンテナ自身のネットワーク設定を操作できるようになる。
* 悪い点: 隔離が有効になるのは`up`がルールを適用した後であり、コンテナ起動からその間にわずかな窓がある。現在のイメージの`CMD`は`sleep infinity`で、この間にサンドボックス内のプロセスは動かないため実害はないが、ticket 03 以降でコンテナ起動時にClaude Codeを自動起動する構成にする場合は再検討が必要になる。
* 悪い点: IPv6は対象外。現在Dockerがこれらのコンテナにv6アドレスもルートも与えていないため今は塞ぐものがないが、IPv6を有効にしたdaemonでは同等の`ip6tables`ルールが必要になる。

### 遵守の確認

`test/network_isolation.bats` のE2Eテストで確認する。ホスト側に`0.0.0.0`バインドと`127.0.0.1`バインドのリスナーを立て、サンドボックスから`host.docker.internal`経由・bridge gateway経由の双方で到達できないこと、インターネット到達とDNS解決が維持されること、`up`の再実行後も隔離が維持されること（冪等性）を検証する。ホスト側の権限を必要としないため、macOS・Linuxのどちらでもそのまま実行できる。

## 各選択肢の利点と欠点

### 選択肢A: コンテナ内iptables + owner match

* 良い: ホスト側にiptablesが無くても機能する。macOS実機（OrbStack、Docker Engine 29.4.0、Kernel 7.0.14-orbstack）で`host.docker.internal:18901`への到達がブロックされ、ルールをflushすると同じ経路でHTTP 200が返ることを対比で確認済み（`sandbox/isolate.sh`）
* 良い: DNS解決が維持される。composeが作るuser-defined bridgeではembedded DNSが`127.0.0.11`（loopback）であり、宛先ベースのブロックに巻き込まれない。上流への転送はdockerd側で行われるため`OUTPUT`チェーンの影響を受けない
* 中立: `-j REJECT` を使うため、遮断されたアクセスは即座に失敗する。DROPと違い「遅いネットワーク」に見えず、誤って踏んだことが分かりやすい
* 悪い: rootを隔離できない。sudoでルールを削除可能
* 悪い: `NET_ADMIN` capabilityが必要

### 選択肢B: ホスト種別で分岐し、macOSではVM内でiptablesを実行

* 良い: rootも含めてサンドボックス全体を隔離できる（ADR-0002 の防御力を維持できる）
* 良い: macOSでもDNS解決やインターネット到達への副作用を心配しなくてよい
* 悪い: OrbStackとDocker Desktopそれぞれの内部構造（VMへの侵入方法、ネットワーク構成）に依存する。どちらもその内部構造を公開APIとして保証していないため、アップデートで壊れうる
* 悪い: ホスト種別ごとの分岐が実装とテストの両方に入る。決定要因の1つ目（同一コードパス）を満たさない
* 悪い: Linux側ではホストの`sudo`が引き続き必要で、E2Eテストの自動実行の問題が残る（これが却下の決め手のひとつ）

### 選択肢C: 現状維持（macOSでは隔離をスキップして警告）

* 良い: 実装変更が最小で済む。Linux環境での防御力はADR-0002 のまま維持される
* 悪い: macOSでUser Story 5・7を満たさないままbypass permissionsモードを使うことになる。「隔離が暗黙の前提に依存しない」というUser Story 7の趣旨に正面から反するため却下（これが却下の決め手）

## 未解決の論点

* IPv6経路は実測できていない。現在の環境ではコンテナにIPv6アドレスもルートも存在しないことを確認済みだが、IPv6を有効にしたDocker daemonでの挙動は未検証。
* Docker Desktop（macOS/Windows）での実機検証は未実施。OrbStackでのみ確認している。`host.docker.internal`を実行時解決する実装のため理屈の上では追随するはずだが、Docker Desktopが実際にどのアドレスを返すかは確認していない。
* WSL2/Linux-native Dockerでの実機検証は未実施。ホスト側iptablesに依存しなくなったため成立する見込みは高いが、bridge gateway経由でホストの`0.0.0.0`サービスに到達する経路（Linuxではこれが主経路）が実際に塞がるかは実測が必要。

## 再検討のトリガー

* ticket 03 以降で、コンテナ起動時にClaude Codeを自動起動する構成に変更するとき（起動からルール適用までの窓が実害を持つようになる）
* 防ぎたい対象が「誤操作」から「意図的な脱出」へ変わったとき（rootを隔離できない前提が崩れる）
* Docker daemonでIPv6を有効にするとき

## 追記: ticket 05（DinDサイドカー）での解決

上記で挙げていた「ticket 05 のDinDサイドカーとの関係」は、サブネット全体の除外ではなく、`dind`サービスのアドレスをサービス名で実行時解決して個別に例外化する形で解決した（`sandbox/isolate.sh`の`dind_ip`）。サブネット全体を除外するとbridge gateway自体への到達も許してしまい、`test/network_isolation.bats`が検証している「bridge gateway経由でのホスト到達を塞ぐ」という保証が崩れるため、単一アドレスの例外に留めている。

DinD内で起動されたコンテナ（Testcontainers等）自体の隔離は、本ADRのOUTPUT + owner match方式をそのまま適用できない別の課題だった。それらのコンテナの通信はネストされたdockerdによってNAT・転送されるため、DinDサイドカー自身のFORWARDチェーンを通る一方、owner matchが前提とする「ローカルで生成されたプロセスの所有者」が存在しない。`sandbox/isolate-forward.sh`はDinDサイドカー側でFORWARDチェーンに同じブロック対象を適用することで対応した。

検証中に、DinDサイドカーが自ら管理する`DOCKER-USER`/`DOCKER-FORWARD`チェーンが`FORWARD`チェーンの先頭近くにあり、ACCEPT判定でnetfilterのチェーン走査自体を打ち切ってしまうことが分かった。ルールを`-A`で末尾に追加すると、そのACCEPTより後にしか評価されないため一度も効かない。`sandbox-isolate-forward`は`-I FORWARD 1`で先頭に挿入することでこれを回避している。さらに、`bin/sandbox`側で`apply_dind_network_isolation`を`wait_for_dind`（ネストされたdockerdの起動完了待ち）より先に呼んでいると、この`-I FORWARD 1`を後から追い抜く形でネストされたdockerd自身のチェーン構築が発生しうるレースコンディションになることも分かった。`wait_for_dind`を先に完了させてから`apply_dind_network_isolation`を呼ぶ順序に変更し、ネストされたdockerdが自分のチェーンを構築し終えた後で確実に先頭を取れるようにした。

**`dind_ip`例外がもたらす脅威モデルへの影響について**: この例外により、`dev`ユーザーは（sudoなしで）特権かつTLS無効のDinDサイドカーのDocker APIに全面的にアクセスできる。これは新たなリスクではなく、ADR-0001が受け入れた「特権コンテナはサンドボックスという境界の内側に閉じている」という前提の直接の帰結であり、`dev`ユーザーが既にパスワードなしsudoを持つ（spec User Story 19）のと同じ線引きに乗る。本ADRの脅威モデル（「誤操作や意図しない副作用」を防ぐものであり「意図的な脱出」は対象外）はticket 05でも変わっていない。

**もう1つ、`isolate-forward.sh`側で対称の問題が見つかった。** DinDサイドカーが属するcomposeネットワーク自体のサブネット（例: `172.18.0.0/16`）は、ブロック対象の`172.16.0.0/12`に包含される。本体コンテナがDinD経由で起動したコンテナのpublished portへ接続すると（`docker run -p`でTestcontainersが公開するポートへ本体コンテナから到達する経路そのもの）、その応答パケットはネストされたブリッジからこの外向きインターフェースへ転送されるが、宛先である本体コンテナ自身のアドレスも同じ`172.16.0.0/12`に含まれてしまい、`isolate.sh`の`dind_ip`例外と対になる例外がFORWARD側になければ拒否されてしまう。IPを個別解決して例外化する方式（`dind_ip`と同じやり方）ではなく、`-m conntrack --ctstate ESTABLISHED,RELATED -j RETURN`をブロックルールより前に置く方式で解決した。DinD側から見て「本体コンテナが張った接続の応答」は常にESTABLISHED/RELATEDになる一方、DinD内のコンテナが host 宛てに自発的に張る新規接続はNEW状態のままブロックルールに到達するため、双方向を区別する目的にはIPを解決するより素直で、`sandbox`サービスのアドレスをDNSで解決する必要もない。

実装: `sandbox/isolate-forward.sh`、`sandbox/isolate.sh`の`dind_ip`例外、`bin/sandbox`の`apply_dind_network_isolation`（`wait_for_dind`より後に実行）。

## 補足情報

* ADR-0002 を置き換える。ADR-0002 が記録した「`--internal`ネットワークはインターネットアクセスも遮断してしまうため要件に合わない」「運用ルールのみでは`0.0.0.0`バインドの事故を防げない」という判断は本ADRでも引き続き有効であり、覆していない。変わったのは**ルールをどの層に置くか**だけである。
* 実装: `sandbox/isolate.sh`（ルール本体）、`bin/sandbox` の `apply_network_isolation`、`sandbox/docker-compose.yml` の `cap_add: NET_ADMIN`、`sandbox/Dockerfile` の`iptables`パッケージ追加。
* 検証の経緯は `.scratch/isolated-dev-sandbox/issues/02-network-isolation.md` の Comments に記録している。
