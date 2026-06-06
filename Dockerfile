# syntax=docker/dockerfile:1.7
#
# cfg-server-terraria — thin container around the official Terraria dedicated
# server binary. No mods, no plugins, no Steam dependency — just the upstream
# server zip from terraria.org, extracted onto debian-slim, run as non-root.
#
# Worlds live in /worlds (volume mount). The entrypoint generates a minimal
# serverconfig.txt from env vars on first boot if none is mounted.
#
# Build:
#   docker build -t cfg-server-terraria:local .
#
# Run (local test):
#   docker run --rm -p 7777:7777 -v /tmp/terraria-worlds:/worlds cfg-server-terraria:local
#
# CFG-hosted: core-server provisions one container per user installation via
# the Server Manager kind-registry (kinds/terraria.ts → services/terraria/launch.ts).

ARG TERRARIA_VERSION=1456

FROM debian:bookworm-slim AS extract

ARG TERRARIA_VERSION
ARG TERRARIA_URL=https://terraria.org/api/download/pc-dedicated-server/terraria-server-${TERRARIA_VERSION}.zip

# Download + unpack in a build stage so the final image doesn't carry unzip
# or the original zip. The official zip ships Windows + Mac + Linux builds
# side-by-side; we keep only Linux.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN curl -fsSLo terraria.zip "$TERRARIA_URL" && \
    unzip -q terraria.zip && \
    rm terraria.zip && \
    # Zip extracts as `<version>/Linux/`, `<version>/Mac/`, `<version>/Windows/`.
    # Flatten the Linux dir to /opt/terraria and discard the rest.
    mv */Linux /opt/terraria && \
    rm -rf /build/* && \
    chmod +x /opt/terraria/TerrariaServer.bin.x86_64

# ── Final runtime image ─────────────────────────────────────────────────────
FROM debian:bookworm-slim

ARG TERRARIA_VERSION
LABEL org.opencontainers.image.title="cfg-server-terraria"
LABEL org.opencontainers.image.description="Crit-Fumble Terraria dedicated server container"
LABEL org.opencontainers.image.source="https://github.com/Crit-Fumble/cfg-server-terraria"
LABEL org.opencontainers.image.licenses="AGPL-3.0-only"
LABEL org.opencontainers.image.version="${TERRARIA_VERSION}"

# Terraria's server binary is a 64-bit native ELF that needs libstdc++ +
# libgcc at runtime. tini reaps zombie processes and forwards SIGTERM so
# `docker stop` actually shuts the server cleanly (Terraria writes worlds
# on graceful exit; SIGKILL leaves dirty .wld files).
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates libstdc++6 libgcc-s1 tini && \
    rm -rf /var/lib/apt/lists/* && \
    useradd --system --uid 1000 --user-group --no-create-home --shell /usr/sbin/nologin terraria

COPY --from=extract /opt/terraria /opt/terraria
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# /worlds: where saved worlds live. Mount a per-installation host dir here.
# /opt/terraria: read-only binary tree; non-root user owns nothing in it.
RUN mkdir -p /worlds && chown -R terraria:terraria /worlds

USER terraria
WORKDIR /worlds

EXPOSE 7777/tcp

ENV TERRARIA_WORLD=cfg-world \
    TERRARIA_PORT=7777 \
    TERRARIA_MAXPLAYERS=8 \
    TERRARIA_DIFFICULTY=0 \
    TERRARIA_AUTOCREATE=2 \
    TERRARIA_MOTD="Crit-Fumble Terraria Server"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
