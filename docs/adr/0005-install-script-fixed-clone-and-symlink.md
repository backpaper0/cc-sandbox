# インストールはリポジトリを`~/.cc-sandbox/src`にcloneし、`bin/cc-sandbox`を`~/.local/bin`へsymlinkする方式とする

これまで`cc-sandbox`を使うには、利用者が自分でgit cloneし、`bin/cc-sandbox`を相対/絶対パスで直接叩く必要があった。どこからでも`cc-sandbox`と打てるようにするため、`curl -fsSL <URL> | bash`で取得・実行する`install.sh`を追加した。install.shは、リポジトリ本体を`~/.cc-sandbox/src`にgit cloneし（既にあれば`git pull`で更新）、`bin/cc-sandbox`を`~/.local/bin/cc-sandbox`にsymlinkする。シェルのrcファイル（`~/.bashrc`等）を書き換える方式は、リポジトリの外側であるユーザーのシェル設定に踏み込む副作用が大きく、シェル種別の判定も必要になるため採用しなかった。clone先を`~/.cc-sandbox`直下ではなく`~/.cc-sandbox/src`にしたのは、`~/.cc-sandbox`が既に[ADR-0003](0003-auth-injection-per-host-profile.md)の認証プロファイル（`~/.cc-sandbox/env.<name>`）の置き場所として使われており、そこにリポジトリ本体を直接cloneすると衝突するため。

`~/.local/bin/cc-sandbox`に無関係な既存ファイルがあった場合は無条件で上書きする（curl\|bash系インストーラの慣例）。`~/.cc-sandbox/src`が存在するがgitリポジトリでない場合はエラーで中断し、手動での対処を促す（中身不明のディレクトリを黙って削除・上書きしない）。

## Considered Options

- シェルのrcファイルに`export PATH=...`を追記する方式 — シェル設定への書き込みという副作用が大きく、bash/zsh等の種別判定も必要になるため見送った
- リポジトリ本体をtarballで都度ダウンロードする方式 — gitを前提にできるなら`git pull`による差分更新の方が素直なため見送った
- `~/.cc-sandbox`直下に本体をcloneする方式 — 既存の認証プロファイル置き場と衝突するため却下
