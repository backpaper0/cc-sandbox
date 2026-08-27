# `upgrade`サブコマンドは`CC_SANDBOX_ROOT`に対して`git pull --ff-only`する方式とする

`install.sh`の再実行なしにcc-sandbox本体を最新版に更新したいという要望から、`upgrade`サブコマンドを追加した。対象は`install.sh`が使う固定パス`~/.cc-sandbox/src`ではなく、`bin/cc-sandbox`が起動時に`readlink -f`で解決する`CC_SANDBOX_ROOT`（今実行されているスクリプト自身が属するリポジトリ）とすることで、curlインストール環境・開発クローン直接実行のどちらでも同じコードパスで動作する。更新方式は`install.sh`のプレーンな`git pull`とは異なり`git pull --ff-only`を採用し、開発クローンにローカルコミットや変更が乗っている場合に予期しないマージコミットを作らず、gitのエラーで安全に止める。symlinkの再作成・確認プロンプト・更新後のコミットハッシュ表示はいずれも行わない（`upgrade`が呼べている時点でsymlinkは正しく張られており、更新自体はinstall.sh同様ローリスクな操作のため）。

## Considered Options

- `install.sh`同様に固定パス`~/.cc-sandbox/src`をハードコードする方式 — 開発クローンを直接実行している場合に無関係なディレクトリを操作してしまうため却下
- `install.sh`同様のプレーンな`git pull`にする方式 — 開発クローンでローカルコミットと衝突した場合に意図しないマージコミットを作りうるため却下
