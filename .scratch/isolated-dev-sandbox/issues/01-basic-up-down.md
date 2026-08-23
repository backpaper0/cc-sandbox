# 01: サンドボックスの基本起動/破棄

**What to build:** `bin/sandbox up <project-dir>` を実行すると、mise/uv/Python/Java/Node.js/Vimが入った本体コンテナが起動し、指定したプロジェクトディレクトリがマウントされ、非rootユーザー＋パスワードなし無制限sudoでシェルに入れる。`bin/sandbox down` で破棄できる。ネットワーク隔離・DinD・code-server・認証注入・複数インスタンスはまだ含まない、最小の歩く骨格。

**Blocked by:** None (can start immediately)

**Status:** done

- [x] `bin/sandbox up <project-dir>` がコンテナを起動し、mise, uv, Python, Java, Node.js, Vim がPATH上で使える
- [x] 指定したプロジェクトディレクトリが本体コンテナにbind mountされ、中からファイルの読み書きができる
- [x] コンテナの初期プロセスは非rootユーザーとして起動する
- [x] その非rootユーザーはパスワードなしで`sudo`が使える
- [x] `bin/sandbox down` でコンテナおよび関連するcomposeリソースが破棄される

## Comments

実装済み(`bin/sandbox`, `sandbox/Dockerfile`, `sandbox/docker-compose.yml`)、E2Eテストも`test/basic_up_down.bats`にTDDで先に書いた（実装前にred確認済み）。

**既知の制約**: このエージェントを実行しているセッション自体のDocker daemonが、データルート(`/var/lib/docker`)をbtrfsサブボリューム上に置いた状態で`overlay2`ストレージドライバを使っており、`dpkg`のパッケージ展開が`rename()`で`Invalid cross-device link`(EXDEV)を起こして失敗する既知の非互換を踏む。素のUbuntuイメージに`curl`をaptインストールするだけの最小再現でも発生することを確認済みで、本チケットのDockerfile内容とは無関係。そのため、このセッション内では`bin/sandbox up`の実ビルド・実行によるE2E検証(`test/basic_up_down.bats`のgreen化)ができていない。

`docker compose config`によるcompose定義の構文検証、CLIの引数処理・エラーパス（`up`の必須引数チェック、`down`の複数/ゼロインスタンス時のエラー、slug生成ロジック）は個別に手動確認済み。`bin/sandbox`は`shellcheck`もクリア。

実機（WSL2 Ubuntu / macOS）ではこのbtrfs+overlay2特有の問題は通常発生しないはずだが、**`test/basic_up_down.bats`を実際のターゲット環境で実行してgreenになることの確認が未完了のフォローアップとして残っている**。

`/code-review`で2件の実バグを検出、修正済み:
- `bin/sandbox`の`slugify()`がbasenameのみからslugを作っていたため、パスの異なる同名ディレクトリ（例: `~/work/backend`と`~/side/backend`）でcompose project名が衝突し、`up`が既存の別インスタンスを誤って再構成/破棄しうる欠陥があった。絶対パスのsha256先頭8文字をslugに含める方式に変更し、衝突を解消（軽量コンテナで手動検証済み: 異なるパスで異なるslug、同一パスでは安定して同一slugを生成することを確認）。
- `test/basic_up_down.bats`がCLIのslug生成ロジックを独自に再実装しており、`mktemp -d`が生成するパス中の`.`の扱いが`bin/sandbox`の実装とズレて全アサーションが偽陽性/偽陰性になりうる欠陥があった。プロジェクトディレクトリのbind mount先(`/workspace`)を`docker inspect`で照合してコンテナを特定する方式に変更し、CLI内部のslug方式と無関係に外部観測可能な事実だけで検証するようにした（軽量コンテナで手動検証済み: 複数のsandbox風コンテナが同時に存在する状況でも正しい方を選択できること、一致なしでは空を返すことを確認）。

### 実機検証（フォローアップ完了）

上記の未完了フォローアップ（実際のターゲット環境での`test/basic_up_down.bats`のgreen化）を実施し、**6/6 green**を確認した。

検証環境: macOS (Darwin 25.5.0, arm64) / OrbStack上のDocker Engine 29.4.0 / Docker Compose v5.1.2 / storage driver `overlay2` / bats-core 1.14.0。前セッションで踏んだbtrfs+overlay2のEXDEV問題はこの環境では再現しなかった（想定どおり環境固有の問題だった）。

一方で、環境固有ではない**実バグが2件**見つかり、修正した:

- **イメージがビルドできなかった**: `ubuntu:24.04`はuid/gid 1000の`ubuntu`アカウントを標準で同梱している（22.04以前には無く、24.04で入った変更）。そのため`groupadd --gid 1000 dev`が`GID '1000' already exists`で落ち、イメージビルド自体が通らず全6テストがredだった。`USER_UID`/`USER_GID`を占有している既存アカウントを`getent`で引いて`userdel -r`/`groupdel`してから作成するように`sandbox/Dockerfile`を修正（`ubuntu`決め打ちではなくidベースにしたので、ARGで任意のuid/gidを渡した場合にも効く）。
- **`down`が常に失敗していた**: `cmd_down`が`PROJECT_DIR=""`でcomposeを呼んでおり、compose定義の`${PROJECT_DIR}:/workspace`が`:/workspace`という不正なvolume specになって`invalid spec: :/workspace: empty section between colons`で落ちていた。`down`はリソース削除しかせずbind mountを実体化しないが、composeはファイル読み込み時にspecを検証するため通らない。project dirが判明している場合はそれを、引数なし形式では有効な絶対パスのプレースホルダ(`/nonexistent`)を渡すように修正した。なお`-f`を外せばラベル経由で`down`できることも確認したが、`bin/sandbox down`はユーザーのプロジェクトディレクトリで実行されることが多く、そこに別の`docker-compose.yml`があると誤ってそれを読み込むため、`-f`は維持する方針とした。

テストにも1件、環境依存のアサーションがあったので修正した: `docker top`のUSER列はdaemonホスト側のpasswd DBでuidを解決するため、コンテナ内の`dev`という名前はホストによっては解決されず素の`1000`が出る（OrbStackのLinux VM上で実際にそうなった）。「非rootであること」だけをこの列で判定し、dev本人であることの確認は全ホストで一致する`docker inspect --format '{{.Config.User}}'`に移した。

E2Eテストが覆っていない経路も手動で確認済み: 引数なし`down`（単一インスタンス時に正しく破棄）、稼働ゼロ時の`down`（エラー終了）、複数稼働時の`down`（project dir指定を促してエラー終了）。`bin/sandbox`は`shellcheck`クリーン。
