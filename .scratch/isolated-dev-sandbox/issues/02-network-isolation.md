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

### 実機検証（フォローアップ）とネットワーク隔離方式の変更

macOS実機でフォローアップ検証を行った結果、**ADR-0002の方式（ホスト側`DOCKER-USER`/`INPUT`チェーンへのルール投入）がmacOSでは原理的に成立しないことが判明したため、方式を変更した**（[ADR-0004](../../../docs/adr/0004-network-isolation-in-container-owner-match.md)、ADR-0002をsupersede）。上のチェックリストの要件（ホストの`127.0.0.1`/`0.0.0.0`向けサービスへ到達不可、インターネットへは到達可、ホストに残留物なし）はいずれも満たしているが、**それを実現する層が「ホスト側iptables」から「サンドボックス本体コンテナ内のiptables」へ変わっている**。

**検証環境**: macOS (Darwin 25.5.0, arm64) / OrbStack / Docker Engine 29.4.0 (client darwin/arm64, server linux/arm64) / Storage Driver: overlay2 / Kernel 7.0.14-orbstack / bats (Homebrew)

#### 判明した問題

1. **前セッションでビルド不可だった`sandbox/Dockerfile`は、このホストでは問題なくビルドできた。** 前セッションの`Invalid cross-device link`(EXDEV)エラーは、ネストしたDocker daemon固有の問題だったと確定した。

2. **macOSホストには`iptables`が存在しない**（Docker daemonはOrbStackのLinux VM内で動く）。加えてパスワードなしsudoも未設定。そのため`bin/sandbox up`は`apply_network_isolation`で必ず失敗し、fail-closed設計に従ってコンテナを破棄して`exit 1`していた。結果として**ticket 01の`test/basic_up_down.bats`が6件中5件failするリグレッションが発生していた**（ticket 02実装前は6/6 green）。fail-closed設計自体は正しく機能しており、残留リソースは一切なかった。

3. **ADR-0002が未検証事項として残していた`host.docker.internal`迂回は実在した。** ルール適用なしの状態で実測した結果:

   | 経路 | 結果 |
   | :--- | :--- |
   | bridge gateway `192.168.166.1:18901` | 到達不可（Linux-native Dockerとは挙動が異なる） |
   | `host.docker.internal:18901` | **HTTP 200（到達可能）** |
   | `127.0.0.1:18902` | 到達不可 |

   `host.docker.internal`の解決先は`0.250.250.254`で、**RFC1918の範囲外**。ADR-0002が定めたRFC1918宛DROPルールでは、仮にVM内で実行したとしてもこの経路を塞げない。

#### 採用した方式（ユーザー判断）

「Ubuntuコンテナにiptablesをインストールして非rootユーザーを隔離する。rootユーザーの隔離不可は許容」というユーザーの判断に基づき、サンドボックス本体コンテナ内の`OUTPUT`チェーン + owner match（`-m owner --uid-owner`）で`dev`ユーザーの通信のみを遮断する方式に変更した。

実装前にPoCで成立を確認した（`ubuntu:24.04` + `--cap-add NET_ADMIN`、user-defined bridge上）:
- `dev`(uid 1000) → `host.docker.internal:18901` = 遮断
- `dev` → `example.com` = HTTP 200（インターネット到達維持）
- `dev` からのDNS解決 = 維持
- root → `host.docker.internal` = HTTP 200（隔離対象外、設計通り）

**PoCで見つかった落とし穴**: default bridgeネットワークではresolv.confの`nameserver`が`0.250.250.200`を指すため、ブロック範囲に巻き込まれてDNSごと死ぬ。composeが作るuser-defined bridgeではembedded DNSが`127.0.0.11`（loopback）になるため問題ない（上流への転送はdockerd側で行われ`OUTPUT`チェーンを通らない）。この回帰を捕まえるため、DNS解決を検証するテストを追加した。

#### 変更内容

- `sandbox/isolate.sh`（新規）: コンテナ内で実行される隔離スクリプト。専用チェーン`SANDBOX_ISOLATION`を作り、`up`再実行時はflushして作り直す（冪等）。ブロック対象はRFC1918 3レンジ + `169.254.0.0/16`(link-local) + `100.64.0.0/10`(CGNAT) + **実行時に解決した`host.docker.internal`のIP**。`-j DROP`ではなく`-j REJECT`を使い、遮断されたアクセスがタイムアウト待ちにならず即座に失敗するようにした。
- `sandbox/Dockerfile`: `iptables`パッケージを追加し、`isolate.sh`を`/usr/local/sbin/sandbox-isolate`に配置。
- `sandbox/docker-compose.yml`: `cap_add: NET_ADMIN`を追加。
- `bin/sandbox`: ホスト側iptablesを叩くコードを全廃。`network_subnet_for_project`・`remove_network_isolation`・`RFC1918_RANGES`を削除し、`apply_network_isolation`は`docker exec -u root <cid> /usr/local/sbin/sandbox-isolate dev`の1行になった。`cmd_up`はコンテナID取得を先に行い、ID取得失敗時も含めてfail-closedでteardownする。`cmd_down`はルール除去が不要になり`compose down`のみになった（ルールはコンテナと寿命を共にするため、ホストに残留物が原理的に生じない）。`shellcheck`クリーン。

#### テスト側で見つかったバグ

方式変更後も両テストがfailし続けたが、原因は実装ではなく**テスト側のバグ**だった。macOSの`mktemp -d`は`/var/folders/...`（symlink経由の論理パス）を返すが、`bin/sandbox`はticket 02のcode-reviewで入れた`pwd -P`により`/private/var/folders/...`（物理パス）でマウントする。テストの`container_id()`は`$PROJECT_DIR`とマウントSourceを完全一致で比較するため、コンテナを永久に見つけられなかった。両テストの`setup_file`で`PROJECT_DIR="$(cd "$(mktemp -d)" && pwd -P)"`と正規化して解消。`up`自体は隔離適用まで含め最初から成功していた。

#### 結果

- `test/basic_up_down.bats`: **6/6 green**（リグレッション解消）
- `test/network_isolation.bats`: **8/8 green**

`test/network_isolation.bats`はsudoを一切使わなくなり、ホスト側の権限なしで完走する。テスト内容も方式変更に合わせて書き換えた（`host.docker.internal`経由とbridge gateway経由の両方を検証、DNS解決の検証、`up`再実行後も隔離が維持されることの検証を追加。ホスト側iptablesのルール数を数える検証は不要になったため削除）。

**テストが偽陽性でないことも確認済み**: 同一コンテナで`iptables -F SANDBOX_ISOLATION`を実行してルールを外すと、`dev`から`host.docker.internal:18901`へHTTP 200で到達できるようになる（隔離ありでは`000`）。

#### 残課題

- **specの更新が必要**: `spec.md`のImplementation Decisions「ネットワーク」節はADR-0002（`DOCKER-USER`チェーン方式）を前提とした記述のままになっている。合意文書のためこのセッションでは書き換えていない。
- WSL2/Linux-native Dockerでの実機検証は未実施。ホスト側iptablesに依存しなくなったため成立する見込みは高いが、Linuxでの主経路であるbridge gateway経由の遮断は実測が必要。
- Docker Desktopでの実機検証は未実施（OrbStackのみ）。
- IPv6は対象外。現環境ではコンテナにIPv6アドレス・ルートともに存在しないことを確認済み。
- rootは隔離できない（設計上の許容事項、ADR-0004参照）。
- ticket 05（DinDサイドカー）でブロック範囲の除外設計が必要な点は、ADR-0002の時点から変わらず残っている。
