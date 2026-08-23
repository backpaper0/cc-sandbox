# 08: `sandbox list`コマンド

**What to build:** `bin/sandbox list`で現在起動中の全インスタンス（名前・プロジェクトパス・ポート等）が一覧できる。

**Blocked by:** 06

**Status:** done

- [x] `bin/sandbox list` が現在起動中の全サンドボックスインスタンスを表示する
- [x] 各行にインスタンス名/slug、マウントしているプロジェクトパス、関連ポート（code-server等）が最低限表示される
- [x] 稼働中インスタンスが0件のときは、エラーにならず空である旨が明確に表示される

## Comments

`test/sandbox_list.bats`をE2Eで追加。「0件」のケースは実機のDockerで確認済み(green)。
「インスタンスが実際に動いている場合」のケースは、本セッションの開発コンテナ自体がDockerイメージビルド時のoverlayfsマウントを許可しないため(既存の`basic_up_down.bats`等も同じ理由で実行不可)、このセッションでは実機E2Eを完走できなかった。代わりに、compose相当のラベルを持つコンテナを手動で用意し`list_row`/`cmd_list`のロジック(コンテナ検出・mount元パス取得・code-serverポート取得・0件時の分岐・余分な引数の拒否)を直接検証し、正しく動作することを確認した。WSL2/macOS実機での最終確認は未実施(spec.mdの「完了条件」参照)。
