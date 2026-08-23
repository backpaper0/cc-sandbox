# 01: サンドボックスの基本起動/破棄

**What to build:** `bin/sandbox up <project-dir>` を実行すると、mise/uv/Python/Java/Node.js/Vimが入った本体コンテナが起動し、指定したプロジェクトディレクトリがマウントされ、非rootユーザー＋パスワードなし無制限sudoでシェルに入れる。`bin/sandbox down` で破棄できる。ネットワーク隔離・DinD・code-server・認証注入・複数インスタンスはまだ含まない、最小の歩く骨格。

**Blocked by:** None (can start immediately)

**Status:** in-review

- [ ] `bin/sandbox up <project-dir>` がコンテナを起動し、mise, uv, Python, Java, Node.js, Vim がPATH上で使える
- [ ] 指定したプロジェクトディレクトリが本体コンテナにbind mountされ、中からファイルの読み書きができる
- [ ] コンテナの初期プロセスは非rootユーザーとして起動する
- [ ] その非rootユーザーはパスワードなしで`sudo`が使える
- [ ] `bin/sandbox down` でコンテナおよび関連するcomposeリソースが破棄される

## Comments

実装済み(`bin/sandbox`, `sandbox/Dockerfile`, `sandbox/docker-compose.yml`)、E2Eテストも`test/basic_up_down.bats`にTDDで先に書いた（実装前にred確認済み）。

**既知の制約**: このエージェントを実行しているセッション自体のDocker daemonが、データルート(`/var/lib/docker`)をbtrfsサブボリューム上に置いた状態で`overlay2`ストレージドライバを使っており、`dpkg`のパッケージ展開が`rename()`で`Invalid cross-device link`(EXDEV)を起こして失敗する既知の非互換を踏む。素のUbuntuイメージに`curl`をaptインストールするだけの最小再現でも発生することを確認済みで、本チケットのDockerfile内容とは無関係。そのため、このセッション内では`bin/sandbox up`の実ビルド・実行によるE2E検証(`test/basic_up_down.bats`のgreen化)ができていない。

`docker compose config`によるcompose定義の構文検証、CLIの引数処理・エラーパス（`up`の必須引数チェック、`down`の複数/ゼロインスタンス時のエラー、slug生成ロジック）は個別に手動確認済み。`bin/sandbox`は`shellcheck`もクリア。

実機（WSL2 Ubuntu / macOS）ではこのbtrfs+overlay2特有の問題は通常発生しないはずだが、**`test/basic_up_down.bats`を実際のターゲット環境で実行してgreenになることの確認が未完了のフォローアップとして残っている**。

`/code-review`で2件の実バグを検出、修正済み:
- `bin/sandbox`の`slugify()`がbasenameのみからslugを作っていたため、パスの異なる同名ディレクトリ（例: `~/work/backend`と`~/side/backend`）でcompose project名が衝突し、`up`が既存の別インスタンスを誤って再構成/破棄しうる欠陥があった。絶対パスのsha256先頭8文字をslugに含める方式に変更し、衝突を解消（軽量コンテナで手動検証済み: 異なるパスで異なるslug、同一パスでは安定して同一slugを生成することを確認）。
- `test/basic_up_down.bats`がCLIのslug生成ロジックを独自に再実装しており、`mktemp -d`が生成するパス中の`.`の扱いが`bin/sandbox`の実装とズレて全アサーションが偽陽性/偽陰性になりうる欠陥があった。プロジェクトディレクトリのbind mount先(`/workspace`)を`docker inspect`で照合してコンテナを特定する方式に変更し、CLI内部のslug方式と無関係に外部観測可能な事実だけで検証するようにした（軽量コンテナで手動検証済み: 複数のsandbox風コンテナが同時に存在する状況でも正しい方を選択できること、一致なしでは空を返すことを確認）。
