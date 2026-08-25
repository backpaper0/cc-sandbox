FROM ubuntu:24.04

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000
# Pinned (rather than @latest) so bumping the version invalidates just this build
# layer instead of relying on cache misses that never happen.
ARG CLAUDE_CODE_VERSION=2.1.241
ARG PLAYWRIGHT_MCP_VERSION=0.0.79
ARG PLAYWRIGHT_VERSION=1.63.0-alpha-2026-08-05

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      ca-certificates \
      git \
      sudo \
      vim \
      build-essential \
      unzip \
      xz-utils \
      util-linux \
      iptables \
      docker.io \
    && rm -rf /var/lib/apt/lists/*

# Corporate CA certificate (ticket 12, ADR-0007): bin/cc-sandbox stages
# ~/.cc-sandbox/ca-cert.crt (if present) at this fixed, .gitignore'd path inside
# the build context before every `compose build`. The bracket glob makes the
# COPY a no-op when that file is absent, and the -s check below skips
# update-ca-certificates when it's present but empty. Placed before every later
# RUN step that talks to the network (code-server/mise/uv/npm installs below),
# so those also trust the merged bundle it produces.
COPY ca-cert.cr[t] /usr/local/share/ca-certificates/cc-sandbox-ca.crt
RUN [ -s /usr/local/share/ca-certificates/cc-sandbox-ca.crt ] && update-ca-certificates || true

# update-ca-certificates above only makes OpenSSL-based tools (curl, git) trust
# the merged bundle -- they already default to /etc/ssl/certs/ca-certificates.crt
# without any of this. Node (npm) and Python's requests/pip ship their own
# bundled CA list and ignore the OS trust store entirely, so without these they
# still fail TLS verification under SSL inspection (found in review -- this
# broke the very `npm install -g` a few layers down). Set unconditionally
# (always exists, corporate CA merged in or not) rather than only when a
# corporate CA is present, since pointing at the same file tools already
# default to is a no-op either way.
ENV CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    PIP_CERT=/etc/ssl/certs/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

# Network isolation runs inside the container (see docs/adr/0004); `bin/cc-sandbox up`
# invokes this as root once the container is running. blocked-ranges.sh is shared
# with sandbox/isolate-forward.sh (the DinD sidecar's own isolation, ticket 05),
# which sources it from the same path via a bind mount instead of a build (see
# sandbox/docker-compose.yml's `dind` service).
COPY blocked-ranges.sh /usr/local/sbin/cc-sandbox-blocked-ranges
COPY isolate.sh /usr/local/sbin/cc-sandbox-isolate
RUN chmod 0755 /usr/local/sbin/cc-sandbox-isolate

# Downloaded to a file rather than piped straight into sh: /bin/sh here is dash,
# which has no pipefail, so a failed curl (e.g. a network blip) would otherwise
# hand sh an empty stdin and exit 0, silently producing an image with no
# code-server binary installed at all.
RUN curl -fsSL https://code-server.dev/install.sh -o /tmp/install-code-server.sh \
    && sh /tmp/install-code-server.sh \
    && rm /tmp/install-code-server.sh

COPY entrypoint.sh /usr/local/bin/cc-sandbox-entrypoint
RUN chmod 0755 /usr/local/bin/cc-sandbox-entrypoint

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
RUN npm install -g \
      "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
      "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" \
      "playwright@${PLAYWRIGHT_VERSION}" \
    && mise reshim \
    && claude mcp add playwright --scope user -- \
      playwright-mcp --headless --browser chromium --no-sandbox \
      --output-dir /tmp/playwright-mcp-output

# Installed after the `claude mcp add` step above, which needs the real
# binary: PATH already resolves `claude` through this file's target
# directory (${HOME}/.local/bin, see the ENV PATH line above), so an earlier
# COPY would shadow it during the build too. See CONTEXT.md's "claudeラッパー".
COPY --chown=${USERNAME}:${USERNAME} claude-wrapper.sh "${HOME}/.local/bin/claude"
RUN chmod 0755 "${HOME}/.local/bin/claude"

# Install Chromium's OS libraries into the image and seed the browser cache.
# bin/cc-sandbox repeats the browser install after applying network isolation as a
# cheap no-op, so an already-created ticket-07 cache volume that predates this
# layer is populated safely on first use too.
RUN sudo env PATH="${PATH}" "$(npm prefix -g)/bin/playwright" install-deps chromium \
    && playwright install chromium

# Pre-create the cache directories docker-compose.yml mounts shared volumes onto
# (ticket 07), owned by dev rather than left for Docker to create on first mount.
# A named volume copies the target directory's existing ownership/content from the
# image the first time it's mounted, but only if that directory already exists --
# otherwise Docker creates the mountpoint as root, and dev (a non-root user) can't
# write into it.
RUN mkdir -p "${HOME}/.cache/uv" "${HOME}/.npm" "${HOME}/.m2" "${HOME}/.cache/ms-playwright"

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/cc-sandbox-entrypoint"]
CMD ["sleep", "infinity"]
