# E2Eテスト

受け入れテストスイート一式は次のコマンドで実行する:

```sh
bin/test-e2e
```

このコマンドはローカル実行でもCIでも同じものを使う。Bash、Bats、そして
呼び出し元が特権コンテナを起動できる実際のLinux Dockerデーモンを必要と
する。このスイートはDockerをモックしない: サンドボックスイメージを
ビルドし、実行中のサンドボックス・DinDコンテナに対して公開APIである
`bin/cc-sandbox` CLIを実際に動かして検証する。ネットワーク系のテストは
アウトバウンドのDNS・HTTPSアクセスも必要とする。

このコマンドはspecのTesting Decisionsに列挙された挙動をカバーする:
プロジェクトのマウント、ホストネットワークからの隔離、インターネット
アクセス、DinDとTestcontainers、code-serverの認証、複数インスタンスの
隔離、共有キャッシュの永続化、認証プロファイルの注入、インスタンス一覧、
Playwright MCPのナビゲーション/スクリーンショット/キャッシュ再利用。

## 対話端末から実行する場合の注意

`bats`の`run`は、テストの標準入力を実行元の端末から切り離さない。
`bin/test-e2e`を対話プロンプト（標準入力が実際のtty）から直接実行すると、
`test/auth_profile_injection.bats`の「up --profile with no name fails
clearly in a non-interactive shell」というテストが、たまたま
`select_profile_interactive`の`[[ ! -t 0 ]]`ガード（
[docs/adr/0006](adr/0006-interactive-profile-selection.md)参照）を
すり抜けてしまい、本物の`select`プロンプトに到達し、テストが期待する
即座の失敗ではなく、実際のキーボード入力待ちでブロックすることがある。

これを避けるため、標準入力を端末から切り離して実行する:

```sh
bin/test-e2e < /dev/null
```

## 対象プラットフォーム

受け入れ基準となるのはWSL2またはLinuxネイティブのDockerである。この
スイートはサンドボックスから`host.docker.internal`へのルートが到達
不能であることを検証するが、そのホスト名が名前解決できない場合にも
このアサーションは通ってしまう。そのため、Docker DesktopやOrbStackの
macOS側ホストルーティング実装を検証していると主張するものではない。
このmacOS固有のバイパス経路は`.scratch/isolated-dev-sandbox/spec.md`
において引き続き明示的にスコープ外とされている。

このリポジトリの作業に使われるエージェント実行環境は、ネストされた
overlay/btrfsの組み合わせでデータルートが構成されたDockerデーモンを
公開している場合がある。そのようなデーモンでは、イメージのビルドが
`operation not permitted`や`Invalid cross-device link`で失敗すること
がある。これはサポート対象の検証環境ではないため、対象のWSL2/Linux
ネイティブDockerホスト上でコマンドを実行すること。
