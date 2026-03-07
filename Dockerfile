FROM debian

ARG UID=1000
ARG GID=1000
ARG USERNAME

# パッケージマネージャで必要なものをインストール
RUN <<_EOF_
apt update
apt install -y --no-install-recommends \
  bash-completion \
  ca-certificates \
  curl \
  git \
  jq \
  locales \
  vim
rm -fr /var/lib/apt/lists/*
_EOF_

# 日本語の対応
RUN <<_EOF_
sed -i 's/^# *ja_JP.UTF-8 UTF-8/ja_JP.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=ja_JP.UTF-8
_EOF_

# ユーザーを作成
RUN <<_EOF_
groupadd -g "${GID}" "${USERNAME}"
useradd -u "${UID}" -g "${GID}" -m -s /bin/bash "${USERNAME}"
_EOF_

USER "${USERNAME}"

WORKDIR "/home/${USERNAME}"

SHELL ["/bin/bash", "-c"]

ENV CLAUDE_CONFIG_DIR="/home/${USERNAME}/.claude"
ENV TZ="Asia/Tokyo"
ENV LANG="C.UTF-8"
ENV LC_ALL="C.UTF-8"


# miseをインストール
RUN <<_EOF_
curl https://mise.run/bash | bash
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
_EOF_

# Claude Codeをインストール
RUN <<_EOF_
mkdir ~/.claude
curl -fsSL https://claude.ai/install.sh | bash
echo 'alias claude="claude --allow-dangerously-skip-permissions"' >> ~/.bashrc
_EOF_

# XDG Base Directoryに従ったパスからbashの設定ファイルを読み取る
RUN <<_EOF_
cat <<_INNER_EOF_ >> ~/.bashrc
if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/bash/config" ]; then
    . "${XDG_CONFIG_HOME:-$HOME/.config}/bash/config"
fi
_INNER_EOF_
_EOF_

# 必要なファイル・ディレクトリを準備
RUN <<_EOF_
mkdir -p ~/.claude
mkdir -p ~/.config
mkdir -p ~/.local/share/mise
mkdir -p ~/.local/state/mise
mkdir -p ~/.m2/repository
mkdir -p ~/.m2/wrapper
_EOF_
