#!/usr/bin/env bash
# OrbStack マシンを作成し、mise-bootstrap/ の設定でプロビジョニングする。
# マシンが既に存在する場合は作成をスキップし、プロビジョニングだけを再実行する。
# マシン内で行う処理は provisioning/scripts/ のスクリプトに任せ、ここでは転送と呼び出しだけを行う。
#
# 必要な環境変数:
#   MACHINE_NAME  作成・プロビジョニングするマシンの名前
#   MACHINE_USER  マシン内に作成するユーザー名（作成時のみ使用）
#
# 任意の環境変数:
#   GIT_USER_SIGNINGKEY  マシン内でコミット・タグの署名に使う鍵（設定されていれば署名を有効にする）
set -euox pipefail

# リポジトリのルートへ移動する（どこから実行しても相対パスが通るように）
cd "$(cd $(dirname $0)/../..; pwd)"

if ! orbctl info "$MACHINE_NAME" > /dev/null 2>&1; then
  # --isolate-network: ホスト側のネットワークへのアクセスを遮断する
  # --isolated: ホストのファイルシステムを共有しない
  # --set-password: ユーザーのパスワードを対話的に設定する（sudo で使う）
  orbctl create \
    --isolate-network --isolated \
    --set-password \
    --user "$MACHINE_USER" \
    ubuntu \
    "$MACHINE_NAME"
fi

# --isolated のためマシンからホストのファイルは見えない。
# スクリプトと mise-bootstrap/ を tar で固めて orbctl push で転送し、マシン内で展開する
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
ARCHIVE="cc-sandbox-${TIMESTAMP}.tar.gz"
ARCHIVE_LOCALPATH="/tmp/$ARCHIVE"
WORK_DIR="/tmp/cc-sandbox-${TIMESTAMP}"

tar -czvf "$ARCHIVE_LOCALPATH" provisioning/scripts mise-bootstrap
# 転送先の "." はマシン内ユーザーのホームディレクトリ
orbctl push -m "$MACHINE_NAME" "$ARCHIVE_LOCALPATH" .
orb -m "$MACHINE_NAME" mkdir "$WORK_DIR"
orb -m "$MACHINE_NAME" tar -xzvf "$ARCHIVE" -C "$WORK_DIR"

orb -m "$MACHINE_NAME" "$WORK_DIR/provisioning/scripts/install-mise.sh"

# ORBENV に列挙した環境変数がマシン内のコマンドへ引き継がれる。
# `git config get` は Git 2.46 以降のサブコマンド
GIT_USER_NAME="$(git config get user.name)" \
GIT_USER_EMAIL="$(git config get user.email)" \
GIT_USER_SIGNINGKEY="${GIT_USER_SIGNINGKEY:-}" \
ORBENV=GIT_USER_NAME:GIT_USER_EMAIL:GIT_USER_SIGNINGKEY \
orb -m "$MACHINE_NAME" "$WORK_DIR/provisioning/scripts/run-mise-bootstrap.sh" "$WORK_DIR/mise-bootstrap"

# 後片付け（dotfiles は copy で配置しているので、設定ディレクトリを消しても問題ない）
rm "$ARCHIVE_LOCALPATH"
orb -m "$MACHINE_NAME" rm -f "$ARCHIVE"
orb -m "$MACHINE_NAME" rm -fr "$WORK_DIR"
