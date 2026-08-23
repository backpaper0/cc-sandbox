# 06: 複数インスタンスの相互隔離

**What to build:** `--name`でインスタンスを指定して複数のサンドボックスを同時に起動でき、それぞれ専用のDocker network・volumeを持ち、互いに到達不可（ネットワーク的にもボリューム的にも分離）であることが確認できる。

**Blocked by:** 01, 02

**Status:** done

- [x] 異なる`--name <slug>`を指定した`up`を2回実行すると、2つのインスタンスが同時に起動する
- [x] 各インスタンスは専用のDocker networkと専用のプロジェクトbind mountを持つ
- [x] 一方のインスタンス内のプロセスから、もう一方のインスタンス内で動くサービスに到達できない
- [x] 片方のインスタンスを`down --name <slug>`で破棄しても、もう一方の稼働中インスタンスには影響しない

## Comments

### 実装内容

- `bin/sandbox`: `up`/`down`双方に`--name <slug>`を追加。`--name`が与えられた場合、compose project名はディレクトリのハッシュ由来スラッグ（`compose_project_name`）ではなく、`--name`をサニタイズしたスラッグ（`sanitize_name`/`compose_project_name_for_name`）から決まる。これにより同じディレクトリ・異なるディレクトリのどちらでも、`--name`さえ違えば同時に起動できる。`down --name <slug>`は該当プロジェクトをディレクトリ引数なしで直接落とせる（`PROJECT_DIR`は既存の no-argument 分岐と同じダミー値`/nonexistent`のまま）。
- インスタンス分離そのもの（専用network・専用bind mount・相互到達不可）は、compose project単位で従来から成立していた既存の仕組み（`docker compose -p <project>`が project ごとに専用のuser-defined bridge networkを作る、Dockerのデフォルト挙動として異なるuser-defined bridge network間は相互到達不可）に乗るだけで満たせた。ticket 02/04で敷いたネットワーク隔離（コンテナ内iptables）はコンテナごとに閉じているため、複数同時稼働との組み合わせでも追加の考慮は不要だった。
- `slugify()`と`sanitize_name()`が共有していた「小文字化+`[a-z0-9-]`以外をダッシュに変換」処理を`to_dash_charset()`に共通化。
- `test/helpers.bash`: `container_id()`にプロジェクトディレクトリを明示指定できる引数を追加（省略時は従来通り`$PROJECT_DIR`）。`exec_in_container`（コンテナIDを明示して`docker exec`する版）と`container_ip_of`（同一compose network上の他コンテナから見た到達先IPを取得）を追加。いずれも複数インスタンスを同時に扱う新テストのために必要だった。
- `test/multi_instance_isolation.bats`（新規）: 本チケットの4つの受け入れ条件と、後述のレビュー対応で追加した`--name`衝突ガードを検証する5テスト。

### 実機検証できなかった事情（このセッション固有の環境制約）

ticket 05のコメントに記録済みの制約と同じで、このセッションのDocker daemonは`sandbox/Dockerfile`のビルドがbuildkitでも失敗する（`ubuntu:24.04`ベースの最小`RUN echo hello`のみのDockerfileでも同じ`overlay`マウントの`operation not permitted`エラーで再現し、既存の`test/basic_up_down.bats`（ticket 01、今回の変更を一切含まない）も同じ原因で6件中5件失敗することを確認済み）。このため`test/multi_instance_isolation.bats`を含む全E2Eスイートは、このセッションでは実ビルド経由の実行ができていない。

代わりに、ビルドを経由しない範囲で検証した:

- `bash -n`による構文チェック
- `sanitize_name`/`compose_project_name_for_name`/`to_dash_charset`/`check_name_not_in_use_by_other_dir`を関数単位で切り出し、実際のCLI引数パースと同じ経路（`up`/`down`のオプションループ）を通して境界値（空文字列に潰れる`--name`、ダッシュのみの`--name`、`--name`と位置引数の同時指定、未知オプション、インスタンス0件時の`down`）を確認
- `test/multi_instance_isolation.bats`が構文エラーなくbatsに5テストとして読み込まれることを確認

`bin/sandbox`・`test/helpers.bash`・`test/multi_instance_isolation.bats`はいずれも`bash -n`クリーン（`shellcheck`はこのセッションに未インストールのため未実施）。

### `/code-review`対応

`/code-review`で以下を検出し、本チケットのスコープ内（今回の差分に関係する）ものは修正した:

- **サイレントな乗っ取り（Critical）**: `up <dirB> --name shared`が、既に`up <dirA> --name shared`で起動済みの同名インスタンスに対して`docker compose up -d --build`を実行すると、composeがbind mountの変更を検知してコンテナを再作成し、instance Aのコンテナをinstance Bのものへ黙って差し替えてしまう欠陥があった。`check_name_not_in_use_by_other_dir`を追加し、`--name`で指定した既存インスタンスのbind mount元ディレクトリが今回の引数と異なる場合はfail closedでエラー終了するようにした。`test/multi_instance_isolation.bats`にこのガードを検証するテストを追加した。
- **`--name`のバリデーションが実効性を持たない（Critical、レビューではなく自己検証で発見）**: `sanitize_name`が空文字列時に`exit 1`していたが、これは`project_name="$(compose_project_name_for_name "${name}")"`という代入文の右辺（コマンド置換）の中で呼ばれており、bashの`set -e`は代入文の右辺の失敗を親スクリプトのエラーとして扱わない（`inherit_errexit`が既定で無効なため）。結果として`--name '!'`のような不正な値でもバリデーションエラーを出力しつつDockerビルドまで処理が進んでしまうことを、ビルドなしでは検出できない経路で発見した。`sanitize_name`/`compose_project_name_for_name`を`return 1`に変え、呼び出し側で`|| exit 1`を明示することで修正した。
- **issueファイルの`Status`/チェックボックス未更新（Low）**: 本ファイル。ticket 05は完了時に更新済みだった一方、本チケットは`ready-for-agent`のまま放置されていた。今回の対応で更新した。

見送った指摘（いずれもticket 05で既にコミット済みの既存コードに対するもので、本チケットのスコープ外と判断）:

- `sandbox/isolate.sh`の`dind_ip`解決リトライ中、`SANDBOX_ISOLATION`チェーンが空のまま数秒間トラフィックが素通りする窓がある指摘。ticket 05時点から存在する既知の挙動で、`--name`とは無関係。
- `sandbox/isolate-forward.sh`が`FORWARD`チェーンの先頭固定挿入に依存しており、ネストされたdockerdがセッション途中で自分のチェーンを再構築すると再度追い抜かれうる指摘。ticket 05のADR-0004追記に記録済みの既知のトレードオフ。
- `test/dind_testcontainers.bats`の`gateway_ip_of "$(dind_container_id)"`が空文字列を返した場合にテストが偽陽性で通ってしまう指摘。ticket 05の既存テストで、今回の差分には含まれない。
- `wait_for_dind`/`wait_for_code_server`の逐次実行によるレイテンシの指摘。ticket 05のコメントで既に検討済み・見送り済み（bashでの並列ポーリングの複雑さが見合わない）。

また、`--name`のオプションパース（`--name`/`--name=`の2ブランチ）が`cmd_up`/`cmd_down`に重複しているという指摘があったが、共有するには（`local -n`などbash 4.3+のnameref、またはデリミタを使った文字列往復のいずれか）現状の素朴な実装より複雑になり、`macOS`標準の`/bin/bash`（3.2系）との互換性リスクも生むため見送った。本リポジトリの「過度な抽象化を避ける」方針（3行の重複は早すぎる抽象化より良い）に照らして許容範囲と判断した。

### 残課題

- `test/multi_instance_isolation.bats`を含む全E2Eスイートの実ビルド経由での実行が未完了。ビルド可能な環境（実機のWSL2/macOS）でのフォローアップが必要（ticket 01/02/05と同種の既知の制約）。
- Docker Desktop（macOS/Windows）・WSL2/Linux-native Dockerでの実機検証は未実施。

### ticket 07セッションでの追加修正（`/code-review`で検出、フォローアップ）

ticket 07（キャッシュボリューム永続化）の実装セッションで`/code-review`を走らせた際、ticket 07の差分とは無関係な、この時点で既にコミット済みだった`--name`関連の既存バグ3件が検出された。ユーザーに確認の上、同セッションで（別コミットとして）修正した:

- **`check_name_not_in_use_by_other_dir`が恒常的にno-op化していた（Critical）**: `cmd_up`内でこのガードが`export PROJECT_DIR=...`より前に呼ばれていた。ガード内の`compose "${project_name}" ps -q sandbox 2>/dev/null || true`は、`docker-compose.yml`の`${PROJECT_DIR}:/workspace`（デフォルト値なし）が未設定の`PROJECT_DIR`により`invalid spec: :/workspace: empty section between colons`で失敗するが、その失敗が`2>/dev/null || true`で握りつぶされ、`existing_container`が常に空文字列になっていた。結果、本チケットのコメントで「修正した」と記録していた"サイレントな乗っ取り"（`up <dirB> --name shared`が稼働中の`up <dirA> --name shared`を無言で上書きする）が実質的に再発していた。`export PROJECT_DIR`をガード呼び出しより前に移動し、念のため`check_name_not_in_use_by_other_dir`の冒頭に`PROJECT_DIR`未設定時に即エラー終了するガードも追加した。
- **新規`--name`同士のcheck-then-actレース（High）**: 既存の衝突ガードは「既に起動済みの`--name`と別ディレクトリで衝突していないか」しか見ておらず、2つの`up --name shared`が"どちらもまだ未起動"の状態で競合した場合は両方ガードを通過し、後勝ちで`compose up -d --build`がもう一方のコンテナを上書きしうる状態だった。`mkdir`のアトミック性を使った`acquire_name_lock`を追加し、`--name`が指定されたときはガードの直前でロックを取得、スクリプトの`EXIT`（`up`が成功/失敗いずれで終わっても）でロックを解放するようにした。これによりガードから`compose up -d --build`完了までの区間全体が同名`--name`に対して直列化される。
- **`down`が対象不在でもexit 0で成功していた（Medium）**: `bin/sandbox down --name <実在しない名前>`や、実体は`--name`で起動されたインスタンスを`down <project-dir>`で叩いた場合など、対象のcompose projectが実在しなくても`docker compose ... down`自体はexit 0で成功してしまい、呼び出し側が「本当に破棄できたか」を終了コードから判断できなかった。`compose "${project_name}" down`の直前に`sandbox`サービスのコンテナが実在するかを確認し、いなければエラー終了するチェックを追加した。

いずれも`bash -n`・`shellcheck`はクリーン。このセッションの環境制約（`sandbox/Dockerfile`のビルドがbuildkit・legacy builderいずれでも失敗する）は変わらず解消していないため、`test/multi_instance_isolation.bats`を含む実ビルド経由でのE2E検証は今回も未実施。関数単位（`acquire_name_lock`・`dind_cache_volume_in_use_by_other_project`）の切り出し実行と、`bin/sandbox down --name <未起動>`を実際に呼んでエラー終了することは確認した。
