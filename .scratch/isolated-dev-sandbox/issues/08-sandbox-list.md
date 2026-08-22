# 08: `sandbox list`コマンド

**What to build:** `bin/sandbox list`で現在起動中の全インスタンス（名前・プロジェクトパス・ポート等）が一覧できる。

**Blocked by:** 06

**Status:** ready-for-agent

- [ ] `bin/sandbox list` が現在起動中の全サンドボックスインスタンスを表示する
- [ ] 各行にインスタンス名/slug、マウントしているプロジェクトパス、関連ポート（code-server等）が最低限表示される
- [ ] 稼働中インスタンスが0件のときは、エラーにならず空である旨が明確に表示される
