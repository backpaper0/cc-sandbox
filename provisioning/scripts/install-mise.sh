#!/usr/bin/env bash
# プロビジョニング対象のマシン上で実行し、mise をユーザー権限でインストールする。
# インストール済みなら何もしない。OrbStack に依存しない（Ubuntu / Debian 系を想定）。
set -euo pipefail

MISE_BIN="$HOME/.local/bin/mise"

if [ -x "$MISE_BIN" ]; then
  echo "mise はインストール済み: $MISE_BIN"
  exit 0
fi

# mise のインストーラーの取得に使う curl を用意する（イメージに入っていない場合に備える）
if ! command -v curl > /dev/null; then
  sudo apt update
  sudo apt install --yes curl ca-certificates
fi

# mise を ~/.local/bin/mise にインストールする。ユーザー所有になるので、更新に sudo は要らない。
# mise.run/bash は ~/.bashrc に `eval "$(<フルパス>/mise activate bash)"` も追記する。
# ~/.bashrc が読まれる時点では ~/.local/bin が PATH に入っていないことがあるので
# （Ubuntu の ~/.profile は ~/.bashrc を読んだ後で PATH に足す）、activate はフルパスで呼ぶ必要がある
curl -fsSL https://mise.run/bash | sh
