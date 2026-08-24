# 11: 認証プロファイル名を任意化する

**What to build:** ticket 03で導入した`--profile <private|work>`は`private`/`work`の2値に固定されていた。実運用では私的／業務の二分だけでなく案件・クライアントごとに認証プロファイルを分けたいニーズがあるため、`--profile`に任意の名前（英数字・`-`・`_`）を渡せるようにし、`~/.sandbox/env.<name>`を読み込ませる。

**Blocked by:** 03

**Status:** done

- [x] `bin/sandbox`の`resolve_profile_env_file`から`private`/`work`のホワイトリスト（case文）を撤廃する
- [x] プロファイル名はパス生成に使われるため、安全な文字種（英数字・`-`・`_`）のみを許可するバリデーションに置き換え、`../`等によるパストラバーサルを防ぐ
- [x] usage文言・README・spec.mdの記述を「固定2択」から「任意名」に更新する
- [x] E2Eテスト（`test/auth_profile_injection.bats`）に、`private`/`work`以外の任意名プロファイルが注入されるケースと、不正文字を含む名前が明確なエラーになるケースを追加する

## Comments

- 実装: `resolve_profile_env_file`のcase文（`private | work`のみ許可）を、`^[A-Za-z0-9_-]+$`に対する正規表現バリデーションへ置き換えた。ファイルパスへの直接埋め込み（`${HOME}/.sandbox/env.${profile}`）は変更していないため、許可文字種の制限だけがパストラバーサル対策になっている。
- `docker-compose.yml`・`SANDBOX_ENV_FILE`まわりの仕組みは元々プロファイル名をハードコードしておらず、変更不要だった。
- ADR-0003は「ホストごとにファイルから環境変数を注入する」という決定自体は変えていないため書き換えていない（`private`/`work`はADR本文でも運用例として書かれているのみで、2択に限定する決定ではなかった）。
- 実機Docker環境がないため、`test/auth_profile_injection.bats`の追加・変更ケースは`resolve_profile_env_file`関数を単体で抽出して手動実行し、期待通りのエラー・成功パスになることを確認した（ticket 03と同じ既知の制約）。フルのbats実行はWSL2/macOS実機での次回検証を推奨する。
