# career-ops container
# Base: Playwright image with Chromium preinstalled (matches playwright@1.58.1 in package.json).
# Host kernels that block Playwright's chromium installer (e.g. Ubuntu 26.04) work fine here
# because the browser ships in the image and runs under the image's userland.

FROM mcr.microsoft.com/playwright:v1.61.1-jammy

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=development \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=0 \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    PATH=/home/node/.local/bin:/usr/local/go/bin:$PATH

# Optional: Go toolchain for the dashboard TUI (./dashboard).
# Small footprint, keeps full feature parity with the README setup.
ARG GO_VERSION=1.23.4
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl git tini latexmk texlive-latex-recommended texlive-latex-extra texlive-fonts-recommended texlive-xetex; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64)  go_arch=amd64 ;; \
      arm64)  go_arch=arm64 ;; \
      *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${go_arch}.tar.gz" -o /tmp/go.tgz; \
    tar -C /usr/local -xzf /tmp/go.tgz; \
    rm /tmp/go.tgz; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Non-root user at uid 1000. Playwright images often ship `pwuser`, not `node`.
RUN set -eux; \
    if ! id -u node >/dev/null 2>&1; then \
      if id -u pwuser >/dev/null 2>&1; then \
        usermod -l node pwuser; \
        groupmod -n node pwuser; \
        usermod -d /home/node -m node; \
      elif ! getent passwd 1000 >/dev/null; then \
        groupadd -g 1000 node; \
        useradd -m -u 1000 -g node -s /bin/bash node; \
      else \
        existing="$(getent passwd 1000 | cut -d: -f1)"; \
        usermod -l node "$existing"; \
        groupmod -n node "$(getent group 1000 | cut -d: -f1)"; \
        usermod -d /home/node -m node; \
      fi; \
    fi; \
    mkdir -p /home/node/.claude /home/node/.local /app; \
    chown -R node:node /home/node /app

# Ensure Chromium under /ms-playwright is readable by node
RUN chmod -R a+rX /ms-playwright || true

USER node
WORKDIR /app

# Install Claude as the same user that will run batch / interactive sessions
RUN curl -fsSL https://claude.ai/install.sh | bash

# Drop back only if something must run as root later — usually stay as node
USER node

# Browsers ship in the Playwright base image; skip postinstall's rootful --with-deps.
COPY --chown=node:node package.json package-lock.json* ./
RUN npm install --no-audit --no-fund --ignore-scripts

# The rest of the project is bind-mounted at runtime via docker compose,
# so we don't COPY sources here — keeps the image generic and lets local
# edits show up instantly inside the container.

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bash"]
