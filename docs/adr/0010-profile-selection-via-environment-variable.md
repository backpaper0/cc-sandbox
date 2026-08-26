# `--profile`の自動選択は`CC_SANDBOX_PROFILE`環境変数を読む方式とし、cc-sandbox自身はディレクトリツリー探索を持たない

複数のプロジェクト（例: `~/project_a/repo_1`, `~/project_a/repo_2`, `~/project_b/repo_1`）を掛け持ちし、プロジェクトごとに使う認証プロファイル（[ADR-0003](0003-auth-injection-per-host-profile.md)）が決まっている運用では、`cc-sandbox up`のたびに`--profile <name>`を手打ちする手間が生じる。多くの開発者は既に[mise](https://mise.jdx.dev/)等のツールでプロジェクトルートの設定ファイル（`mise.toml`）から、そのディレクトリ配下に`cd`した時点でディレクトリスコープの環境変数を自動エクスポートする仕組みを持っている。`cc-sandbox up`実行時に`--profile`が省略されていれば`CC_SANDBOX_PROFILE`環境変数の値をプロファイル名として使う方式とし、cc-sandbox自身はカレントディレクトリからプロファイルを引き当てるためのディレクトリツリー探索やmiseとの直接連携を一切持たないことにした。既存のADR-0007（企業CA証明書・プロキシはホスト側ファイルの有無で自動適用する）と同じく、「フラグを増やすのではなく、環境から自動的に決まる性質は環境から取る」という方針の延長にある。

具体的な挙動は次の通り。

- 明示的な`--profile <name>`（値を省略した対話選択を含む）は常に`CC_SANDBOX_PROFILE`より優先される。
- `CC_SANDBOX_PROFILE`が空文字列の場合は未設定と同じ扱いとし、対話選択には倒さない。対話選択は人間がターミナルで`--profile`を打ったときのための挙動であり、環境変数経由の値が意図せず標準入力待ちを起こすのは驚きが大きいため。
- `CC_SANDBOX_PROFILE`が指す`~/.cc-sandbox/env.<name>`が存在しない、または名前の文字種が不正な場合は、`--profile`を明示したときと同じ`resolve_profile_env_file`のfail-closed方針でエラー終了する（[ADR-0006](0006-interactive-profile-selection.md)が既に定めた「黙って続けず失敗する」方針を踏襲）。
- `CC_SANDBOX_PROFILE`経由でプロファイルが決まった場合のみ、`Using profile: <name> (from $CC_SANDBOX_PROFILE)`をエラー出力に表示する。明示`--profile`はコマンドラインに既に名前が見えているため表示しない。認証情報の注入元がその回のコマンドラインから読み取れなくなる分、可視性を確保する必要があると判断した。
- 環境変数名は`CC_SANDBOX_PROFILE`とし、既存の`CC_SANDBOX_ENV_FILE`等と同じ`CC_SANDBOX_*`プレフィックスに合わせた。これらの既存変数はcc-sandboxが内部的にexportして`docker-compose`へ渡す出力用途だが、`CC_SANDBOX_NOTIFY_COOLDOWN_SECONDS`のようにテスト等の外部から上書きする入力用途の変数も同じプレフィックスに既に混在しており、区別する必要は薄いと判断した。
- `CC_SANDBOX_PROFILE`がセットされたシェルから、その回だけプロファイルなしで起動したい場合の専用フラグ（例: `--profile=none`）は用意しない。必要ならシェル側で一時的に`CC_SANDBOX_PROFILE`をunsetすれば足りる。

`--profile`は`up`にしか存在しない（`down`/`exec`/`password`は起動済みコンテナに対する操作であり、認証情報の注入とは無関係）ため、`CC_SANDBOX_PROFILE`の参照も`up`に限定する。

## Considered Options

- cc-sandbox自身がカレントディレクトリから上位へ設定ファイル（例: `.cc-sandbox-profile`）を探索する方式 — miseに依存せず使える利点はあるが、miseが既に解決済みの「ディレクトリごとの設定」をcc-sandbox側で再実装することになり、既にmiseを使っている開発者にとっては冗長なため見送った。
- `CC_SANDBOX_PROFILE`が空文字列やfile-not-foundのとき、エラーにせず黙ってプロファイルなしにフォールバックする方式 — 「プロファイルが指定されているつもりで実は無効化されていた」状態は、bypass permissionsで動くサンドボックスが未認証のまま起動する紛らわしい失敗モードになり、ADR-0006が確立したfail-closedの方針とも矛盾するため見送った。
- `CC_SANDBOX_PROFILE`経由の選択結果を表示しない方式 — コマンドラインに何も打っていないのにプロファイルが決まる以上、既存の`--profile`（対話選択時のみ`Using profile: <name>`を表示）より不可視性の代償が大きいと判断し、常に表示する方式を採った。
