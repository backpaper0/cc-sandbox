# 02: ネットワーク隔離（サンドボックス→ホスト遮断）

**What to build:** `up`実行時に`DOCKER-USER` iptablesチェーンへルールが追加され、本体コンテナからホストの`127.0.0.1`/`0.0.0.0`向けサービスいずれにも到達できなくなる一方、インターネットへは到達できる。`down`時にルールが除去される。

**Blocked by:** 01

**Status:** done

- [x] `up`がインスタンスのネットワークからホストのRFC1918プライベートIP帯への到達をDROPする`DOCKER-USER`ルールを投入する
- [x] `127.0.0.1`限定でlistenしているホスト側サービスにコンテナ内から到達できない
- [x] `0.0.0.0`でlistenしているホスト側サービスにもコンテナ内から到達できない
- [x] コンテナからパブリックインターネットへは到達できる（DNS解決および既知の到達可能ホストへの接続が成功する）
- [x] `down`実行時にiptablesルールが除去され、ホストに残留しない

## Comments

実装済み(`bin/sandbox`に`network_subnet_for_project`/`apply_network_isolation`/`remove_network_isolation`を追加)。E2Eテストは`test/network_isolation.bats`に先に書いた。

**ADRの前提を1点修正した**: ADR-0002は「`DOCKER-USER`チェーンへのRFC1918宛DROPルールのみ」を想定していたが、実装前にDocker製のuser-defined bridgeネットワーク上で実測したところ、`0.0.0.0`でlistenしている外側サービスは、コンテナからそのネットワークの**ゲートウェイIP**（ホスト自身が所有するアドレス）宛てに到達している。`DOCKER-USER`はFORWARDチェーンのフックであり、宛先がホスト自身の所有アドレスであるパケットはルーティング上「ローカル配送」と判定されFORWARDを通らずINPUTチェーンへ渡るため、`DOCKER-USER`だけではこの経路をDROPできないことを確認した（`curlimages/curl`コンテナ+手動構築したuser-defined bridge+ホスト側`0.0.0.0`/`127.0.0.1`双方向のリスナーで検証：DOCKER-USERのみではゲートウェイIP経由の`0.0.0.0`向け到達がHTTP 200のまま残った）。そのため`DOCKER-USER`（インスタンスsubnet→他のRFC1918宛、他インスタンス/LAN機器向けの多層防御）に加えて、`INPUT`チェーンにインスタンスsubnet発の全トラフィックをDROPするルール（ホスト自身への到達を遮断、`0.0.0.0`バインドサービスを塞ぐ）を追加した。両方とも`-m comment --comment "sandbox:<project-name>"`でタグ付けし、`down`時にコメント一致ではなくsubnet一致で対称的に除去する（`down`はネットワーク破棄前にsubnetを読み取っておくが、ルール除去自体は`compose down`成功後に行う。理由は下記の`/code-review`対応を参照）。`up`の再実行時に古いルールが積み上がらないよう、適用前に同じprojectのルールを一度除去する（冪等）。

ネットワークの特定は、compose默认networkの命名規約（`<project>_default`）に依存せず、`docker network ls --filter label=com.docker.compose.project=<project-name>`で行う（ticket06以降でネットワーク定義が変わっても壊れないようにするため）。

**既知の制約（ticket 01と同じセッション環境固有の問題）**: このセッションのDocker daemonは`bin/sandbox up`が使う実際の`sandbox/Dockerfile`のビルド（`apt-get install`を含むRUN命令）で、buildkit/legacy builderいずれでも`Invalid cross-device link`(EXDEV)相当のエラーを起こし失敗する（ticket 01のComments参照、素のUbuntuに`curl`を入れるだけの最小再現でも発生済み）。そのため本チケットの実装は、このセッションでは`bin/sandbox up`の実ビルド経由でのE2E検証(`test/network_isolation.bats`のgreen化)ができていない。

その代わりに、ビルドを経由しない検証で本チケットの中核ロジック（`network_subnet_for_project`/`apply_network_isolation`/`remove_network_isolation`）を実機のDocker daemon・実iptables・実docker composeネットワークに対して直接検証した:
- `busybox`イメージによるcompose project（ビルド不要）を実際に`docker compose up`し、`bin/sandbox`をsourceして上記関数をそのprojectに対して呼び出した
- 適用前: ホストの`0.0.0.0`バインドサービスへゲートウェイIP経由で到達可能、`127.0.0.1`バインドサービスへは元々到達不可、インターネットへは到達可能、を確認
- 適用後: `0.0.0.0`バインドサービスへの到達がブロックされる、`127.0.0.1`は引き続き到達不可、インターネットへの到達は維持される、を確認
- 二重適用してもルール数が増えない（冪等）ことを確認
- 除去後、`DOCKER-USER`/`INPUT`双方のルールがベースライン状態に戻ることを確認

`bin/sandbox`は`shellcheck`クリーン。

**`test/network_isolation.bats`を実際のターゲット環境（WSL2/macOS実機）で実行してgreenになることの確認が未完了のフォローアップとして残っている**（ticket 01と同種の残課題）。

### `/code-review`対応

`/code-review`で以下を検出・修正した（いずれも同じbusybox代替project + `bin/sandbox`をsourceした関数呼び出しで再検証済み）:

- **fail-openバグ（Critical）**: `apply_network_isolation`がネットワーク特定失敗時に警告を出すだけで`return 0`しており、`cmd_up`は戻り値を見ていなかったため、隔離ルールがゼロのまま`up`が成功扱いになりうる欠陥があった（spec Story #7「隔離が暗黙の前提に依存しない」に反する）。`network_subnet_for_project`/`apply_network_isolation`は失敗時に非ゼロを返すよう変更し、`cmd_up`はその戻り値を見て失敗時にはたった今起動したコンテナを`compose down`で片付けてから`exit 1`する（fail-closed）。`apply_network_isolation`内の各`iptables -I`呼び出しも個別にチェックし、途中で失敗したら挿入済みの分をロールバックしてから失敗を返す。
- **`network_subnet_for_project`のあいまい一致（Medium）**: `docker network ls`が同じprojectラベルの複数ネットワークを返した場合に`head -n1`で決め打ちしていたため、孤児ネットワークが残っていると誤ったネットワークへ隔離ルールを適用しうる欠陥があった。一致数がちょうど1件でない場合は失敗として扱うよう変更（上記fail-closed経路に合流する）。
- **`down`の順序（Medium）**: `compose down`失敗時に隔離ルールだけ先に消えてコンテナが無防備なまま残る欠陥があった。順序を「subnetを読む→`compose down`→ルール除去」に変更し、`compose down`が失敗したら（`set -e`で即終了し）ルールは消さずコンテナは隔離されたまま残るfail-closedにした。
- **symlinkを含むパスでのslug不一致（Medium、ticket 01由来）**: `cd "$1" && pwd`はシンボリックリンクを解決しない論理パスを返すため、`~/code/proj`（`~/code`がsymlink）と実体パスの両方から同じプロジェクトを指しても異なるcompose project名になり、`down`が対象を見失ったり`up`が重複インスタンスを作りうる欠陥があった。`pwd -P`（物理パス解決）に変更。
- **将来の既知の制約としてコード内にコメントを追加**: `RFC1918_RANGES`はサンドボックス自身のサブネットも含むため、ticket05でDinDサイドカーが同じネットワークに同居すると本体コンテナ↔サイドカー間通信も一緒にDROPされてしまう。ticket05側で対処が必要な旨をコード上に明記した。

見送った指摘: なし（全指摘に対応済み）。
