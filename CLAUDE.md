## Agent skills

### スコープ

本リポジトリのドメインは Docker ベースのサンドボックスツール本体（`bin/`, `sandbox/`, `docs/`, `test/`、ルートの `README.md`/`CONTEXT.md`）。同居している `cc-sandbox-legacy/`（旧バージョンのバックアップ）と `orbstack-linux-machines/`（OrbStack の Linux machine 用の別ツール）はこのツールとは無関係な別物。ドメインドキュメント（`CONTEXT.md`、ADR）にも issue tracker（`.scratch/`）にも含めず、参照・編集の対象としない。

### Issue tracker

Issue はローカル Markdown(`.scratch/`)で管理します。See `docs/agents/issue-tracker.md`.

### Domain docs

single-context 構成です。See `docs/agents/domain.md`.

### 言語

ヘルプ（CLIの`--help`/usage出力、エラーメッセージ）やユーザー向けドキュメント（README、`docs/e2e-testing.md`等）は日本語で書く。対象外は `docs/agents/*.md`（AIエージェント向け指示書）、コード内コメント、コミットメッセージ。詳細は [ADR-0011](docs/adr/0011-help-and-docs-in-japanese.md) を参照。
