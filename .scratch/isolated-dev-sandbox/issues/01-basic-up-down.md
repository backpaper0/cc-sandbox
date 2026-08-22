# 01: サンドボックスの基本起動/破棄

**What to build:** `bin/sandbox up <project-dir>` を実行すると、mise/uv/Python/Java/Node.js/Vimが入った本体コンテナが起動し、指定したプロジェクトディレクトリがマウントされ、非rootユーザー＋パスワードなし無制限sudoでシェルに入れる。`bin/sandbox down` で破棄できる。ネットワーク隔離・DinD・code-server・認証注入・複数インスタンスはまだ含まない、最小の歩く骨格。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] `bin/sandbox up <project-dir>` がコンテナを起動し、mise, uv, Python, Java, Node.js, Vim がPATH上で使える
- [ ] 指定したプロジェクトディレクトリが本体コンテナにbind mountされ、中からファイルの読み書きができる
- [ ] コンテナの初期プロセスは非rootユーザーとして起動する
- [ ] その非rootユーザーはパスワードなしで`sudo`が使える
- [ ] `bin/sandbox down` でコンテナおよび関連するcomposeリソースが破棄される
