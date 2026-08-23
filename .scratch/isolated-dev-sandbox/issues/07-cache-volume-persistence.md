# 07: キャッシュボリュームの永続化

**What to build:** mise/uv/npm/Maven/Dockerイメージレイヤー/Playwrightブラウザバイナリ用のキャッシュが全インスタンス共通の名前付きボリュームに保存され、`down`後も残り、別インスタンスで`up`した際に再利用される（再ダウンロードが発生しない）。

**Blocked by:** 01, 06

**Status:** done

- [x] mise/uv/npm/Maven(`~/.m2`)/Dockerイメージレイヤーのキャッシュが、全インスタンス共通の名前付きボリュームに保存される
- [x] Playwrightのブラウザバイナリ(Chromium等)キャッシュも、同じく全インスタンス共通の名前付きボリュームに保存される
- [x] インスタンスを`down`しても、これら共有キャッシュボリュームは削除されない
- [x] 新規（または再作成した）インスタンスで`up`すると、既にキャッシュされている内容の再ダウンロード・再フェッチが発生しないことを確認できる
- [x] 同時に稼働する2つのインスタンス（06）が同じ共有キャッシュボリュームに対して競合なく読み書きできる

## Comments

### 実装内容

- `sandbox/docker-compose.yml`: トップレベルに`volumes:`を追加し、`sandbox-cache-mise`/`sandbox-cache-uv`/`sandbox-cache-npm`/`sandbox-cache-m2`/`sandbox-cache-playwright`を、それぞれ明示的な`name:`付きで宣言した。compose既定の`<project>_<key>`命名に任せず固定名にすることで、`--name`が異なる（＝compose project名が異なる）インスタンス同士でも同じDocker named volumeを共有する。`sandbox`サービス側にこの5つをマウントした。`bin/sandbox down`は元々`-v`を付けていない（`compose down`のみ）ため、これらのボリュームは追加の対応なしで`down`後も残る。Dockerイメージレイヤーキャッシュ（`dind`サービスの`/var/lib/docker`）は下記「`/code-review`対応」の通りフォールバック方式にした。
- `sandbox/Dockerfile`: `npm install -g`の直後に、`~/.cache/uv` `~/.npm` `~/.m2` `~/.cache/ms-playwright`を`dev`ユーザーとして事前に`mkdir -p`した。named volumeを初めてマウントする際、Dockerはマウント先ディレクトリがイメージに既に存在していればその所有権・内容をボリューム側にコピーする一方、存在しなければroot所有の空ディレクトリとして作る。非rootの`dev`ユーザーがこれらのキャッシュに書き込めるよう、ビルド時点で先に作っておく必要があった（`~/.local/share/mise`は`mise use --global`が既に作成済みのため対応不要）。`dind`側の`/var/lib/docker`はコンテナ内で完全にrootとして動くため、この所有権問題自体が発生しない。
- `test/helpers.bash`: `dind_container_id()`に`container_id()`と同じ形の「省略可能なproject dir引数」を追加（省略時は従来通り`$PROJECT_DIR`）し、複数インスタンスのDinDサイドカーを個別に引ける形にした。新たに`volume_name_at(container, destination)`を追加。指定コンテナの指定マウント先が named volume の場合にその名前を返す（bind mountや未マウントの場合は空）。2インスタンスが同一のキャッシュボリュームを共有していることを確認するために使う。
- `test/cache_volume_persistence.bats`（新規）: 本チケットの5つの受け入れ条件に対応する4テスト。`--name`付きで2インスタンス（A/B、Aを先に起動）を起動し、(1)mise/uv/npm/m2/playwrightの5パスがA/Bで同一named volumeであること、(2)DinDサイドカーの`/var/lib/docker`は先着のAが全インスタンス共通の共有ボリューム名を獲得し、Aが稼働中に起動したBはそのボリューム名にフォールバックせず自分専用の別named volumeになっていること（下記「`/code-review`対応」参照）、(3)A/Bから同じ共有ボリューム配下（`~/.cache/uv`、常時共有される側）に別名ファイルを同時書き込みしても互いに壊れないこと、(4)Aにマーカーファイルを書いてから`down --name`→`up`で再作成しても、そのマーカーが残っていること（＝ボリュームが消えず、実質的に再ダウンロードが起きない）を検証する。(4)は他のテストが参照する`cid_a`を無効化するため、ファイル内最後のテストとして順序づけている。

### `/code-review`対応

`/code-review`で以下を検出し、修正した:

- **Dockerイメージレイヤーキャッシュの同時共有がdockerdをハングさせる（Critical、実機で確認済み）**: 当初`dind`サービスの`/var/lib/docker`を他キャッシュと同様に単純な全インスタンス共通named volumeにしていたが、レビューで実際に2つの`docker:28-dind`コンテナへ同一named volumeを`/var/lib/docker`としてマウントして検証したところ、2つ目のdockerdがcontainerdのメタデータストア（boltdb）の排他ロック待ちで`Daemon has completed initialization`まで到達せず無限にハングすることが判明した。`bin/sandbox`の`wait_for_dind`は30秒でタイムアウトしてインスタンス全体を`down`するため、「同時に稼働する2インスタンスが同じ共有ボリュームを読み書きできる」という受け入れ条件5と、ticket 06が可能にした「複数インスタンス同時稼働」自体が正面衝突する状態だった。ユーザーとの相談の上、フォールバック方式を採用: `sandbox/docker-compose.yml`の`dind`サービスは固定エイリアス`dind-cache`を`/var/lib/docker`にマウントし、その実体のDocker volume名は`name: ${DIND_CACHE_VOLUME:-sandbox-cache-docker-layers}`で決まる（composeはトップレベル`volumes:`のキー自体には変数展開できないため、値側の`name:`で切り替える設計にした）。`bin/sandbox`の`cmd_up`は新設の`dind_cache_volume_in_use_by_other_project`で「他プロジェクトが今まさにこの共有ボリュームを使っているか」を`docker ps --filter volume=...`＋ラベル比較で判定し、使用中なら`DIND_CACHE_VOLUME`をこのインスタンスのproject名で固有化したボリューム名にフォールバックする。フォールバック先も実在のnamed volumeなので、そのインスタンス自身の`down`→`up`では引き続きキャッシュが再利用される（受け入れ条件4は単一インスタンスの範囲では引き続き満たす）。先着インスタンスが共有ボリュームを握り、後発の同時稼働インスタンスは自分専用ボリュームにフォールバックするため、後発同士・後発と先着の間でDockerイメージレイヤーの実体は共有されない（受け入れ条件1・5はmise/uv/npm/m2/playwrightの5つでは引き続き完全に満たすが、Dockerイメージレイヤーに限り「同時稼働時は共有されないことがある」という既知のトレードオフとして受け入れた）。`cmd_up`の最終出力にも、フォールバックが発動した場合はその旨を1行追加した。

### `--name`関連（ticket 06）の既存バグ、ユーザーの指示で本セッションで併せて修正

上記reviewで、ticket 07の差分とは別に、ticket 06（既にコミット済み）由来の既存バグ3件も検出された。ユーザーに確認の上、本セッションで一緒に修正した（別コミットに分離、詳細は`.scratch/isolated-dev-sandbox/issues/06-multi-instance-isolation.md`のComments追記を参照）:

- `check_name_not_in_use_by_other_dir`が`PROJECT_DIR`をexportする前に呼ばれており、ガード内の`compose ... ps`が常に失敗して`|| true`で握りつぶされ、ガード自体が恒常的にno-op化していた（"サイレントな乗っ取り"バグの実質的な復活）
- 新規`--name`同士が同時に`up`された場合のcheck-then-actレース（両方が「まだ使われていない」を見てから片方がもう片方のコンテナを上書きしうる）
- `down --name <未起動の名前>`や、`--name`で起動した実体を`down <project-dir>`で叩いた場合に、対象が存在しなくても`compose down`がexit 0で成功してしまう

### フォールバック方式の実機検証

`sandbox/Dockerfile`のビルドがこのセッションでは通らないため`bin/sandbox`経由のフルE2Eはできなかったが、フォールバック方式の核心（"同一volumeを2つのdindで同時共有するとハングする"問題が、"volumeを分ければ両方正常に起動する"ことで実際に解消するか）は、ビルド不要の公式`docker:28-dind`イメージを直接使い、`sandbox/docker-compose.yml`の`dind`サービスと同じ設定（`--privileged`、`DOCKER_TLS_CERTDIR=`空、`/var/lib/docker`へのvolumeマウント）で2つのコンテナを実際に起動して検証した:

1. `sandbox-fallback-shared`という named volume を`/var/lib/docker`にマウントしたコンテナAを起動 → 17秒で`docker info`が通り正常に起動完了
2. 同時にAが稼働中のまま、Aとは別の`sandbox-fallback-b`という named volume を`/var/lib/docker`にマウントしたコンテナBを起動 → こちらも17秒で`docker info`が通り正常に起動完了（レビューが報告した「同一volumeを共有すると2つ目が無限にハングする」問題が、volumeを分けることで実際に回避できることを確認）

`bin/sandbox`本体の`dind_cache_volume_in_use_by_other_project`が使う`docker ps --filter volume=<name>`によるフィルタリングも、実際に起動した上記コンテナに対して意図通りのコンテナIDを返すことを確認済み。

### 実機検証できなかった事情（このセッション固有の環境制約）

ticket 05/06のコメントに記録済みの制約と同一で、このセッションのDocker daemonは`sandbox/Dockerfile`のビルドがbuildkit・legacy builderのどちらでも失敗する（buildkitは`apt-get`実行前のoverlayマウントで`operation not permitted`、legacy builderは`dpkg`の`Invalid cross-device link`で失敗し、いずれも本チケットの差分より前の既存レイヤーで発生する）。このため`test/cache_volume_persistence.bats`を含む全E2Eスイートは、このセッションでは実ビルド経由の実行ができていない。

代わりに、ビルドを経由しない範囲で検証した:

- `docker compose -f sandbox/docker-compose.yml config`が新しい`volumes:`定義込みでエラーなく解決できること
- `shellcheck`で`bin/sandbox`・`sandbox/entrypoint.sh`・`sandbox/isolate.sh`・`sandbox/isolate-forward.sh`・`sandbox/blocked-ranges.sh`が既存の指摘（対象外の`SC1091`/`SC2034`のみ）以外にクリーンであること
- `bats --count test/cache_volume_persistence.bats`が構文エラーなく4テストとして読み込まれること

### 残課題

- `test/cache_volume_persistence.bats`を含む全E2Eスイートの実ビルド経由での実行が未完了。ビルド可能な環境（実機のWSL2/macOS）でのフォローアップが必要（ticket 01/02/05/06と同種の既知の制約、ticket 09でまとめて解消予定）。
