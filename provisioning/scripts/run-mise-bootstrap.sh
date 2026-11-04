#!/usr/bin/env bash
# プロビジョニング対象のマシン上で実行し、mise-bootstrap/ の設定で mise bootstrap を実行する。
# 先に install-mise.sh で mise をインストールしておくこと。OrbStack には依存しない。
#
# 使い方: run-mise-bootstrap.sh <mise-bootstrap ディレクトリ>
#
# 必要な環境変数（dotfiles/gitconfig.tera の展開に使う）:
#   GIT_USER_NAME   Git のユーザー名
#   GIT_USER_EMAIL  Git のメールアドレス
#
# 任意の環境変数:
#   GIT_USER_SIGNINGKEY  コミット・タグの署名に使う鍵（設定されていれば署名を有効にする）
set -euo pipefail

CONFIG_DIR="${1:?mise-bootstrap ディレクトリを指定してください}"
: "${GIT_USER_NAME:?GIT_USER_NAME を設定してください}"
: "${GIT_USER_EMAIL:?GIT_USER_EMAIL を設定してください}"

# 初回は ~/.local/bin が PATH に入っていないことがあるので、mise はフルパスで呼ぶ
MISE_CONFIG_FILE="$(cd "$CONFIG_DIR"; pwd)/mise.toml" \
  "$HOME/.local/bin/mise" bootstrap --yes
