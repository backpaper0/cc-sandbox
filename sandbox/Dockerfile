FROM ubuntu:24.04

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000
# Pinned (rather than @latest) so bumping the version invalidates just this build
# layer instead of relying on cache misses that never happen.
ARG CLAUDE_CODE_VERSION=2.1.241

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      ca-certificates \
      git \
      sudo \
      vim \
      build-essential \
      unzip \
      xz-utils \
      iptables \
      docker.io \
    && rm -rf /var/lib/apt/lists/*

# Network isolation runs inside the container (see docs/adr/0004); `bin/sandbox up`
# invokes this as root once the container is running. blocked-ranges.sh is shared
# with sandbox/isolate-forward.sh (the DinD sidecar's own isolation, ticket 05),
# which sources it from the same path via a bind mount instead of a build (see
# sandbox/docker-compose.yml's `dind` service).
COPY blocked-ranges.sh /usr/local/sbin/sandbox-blocked-ranges
COPY isolate.sh /usr/local/sbin/sandbox-isolate
RUN chmod 0755 /usr/local/sbin/sandbox-isolate

# Downloaded to a file rather than piped straight into sh: /bin/sh here is dash,
# which has no pipefail, so a failed curl (e.g. a network blip) would otherwise
# hand sh an empty stdin and exit 0, silently producing an image with no
# code-server binary installed at all.
RUN curl -fsSL https://code-server.dev/install.sh -o /tmp/install-code-server.sh \
    && sh /tmp/install-code-server.sh \
    && rm /tmp/install-code-server.sh

COPY entrypoint.sh /usr/local/bin/sandbox-entrypoint
RUN chmod 0755 /usr/local/bin/sandbox-entrypoint

# ubuntu:24.04 ships a stock "ubuntu" account at uid/gid 1000, which collides
# with the dev user below whenever USER_UID/USER_GID point at an occupied id.
RUN existing_user="$(getent passwd "${USER_UID}" | cut -d: -f1)" \
    && if [ -n "${existing_user}" ]; then userdel -r "${existing_user}"; fi \
    && existing_group="$(getent group "${USER_GID}" | cut -d: -f1)" \
    && if [ -n "${existing_group}" ]; then groupdel "${existing_group}"; fi \
    && groupadd --gid "${USER_GID}" "${USERNAME}" \
    && useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USERNAME}" \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}" \
    && chmod 0440 "/etc/sudoers.d/${USERNAME}"

USER ${USERNAME}
ENV HOME=/home/${USERNAME}
WORKDIR ${HOME}

ENV PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:${PATH}"
# Use pre-built toolchains instead of compiling Python from source on every image build.
ENV MISE_PYTHON_COMPILE=0

RUN curl -fsSL https://mise.run | sh

RUN mise use --global python@3.12 node@22 java@temurin-21

RUN curl -fsSL https://astral.sh/uv/install.sh | sh

# `mise reshim` makes the globally-installed `claude` binary visible on PATH
# through mise's node shim (see docs/adr/0003 for how auth reaches it).
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" && mise reshim

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/sandbox-entrypoint"]
CMD ["sleep", "infinity"]
