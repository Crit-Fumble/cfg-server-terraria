# syntax=docker/dockerfile:1.7
#
# cfg-server-terraria — Terraria dedicated server container, running TShock.
#
# TShock (Pryaxis/TShock) wraps the official server engine 1:1 for gameplay —
# existing vanilla .wld worlds load unchanged — and adds the piece the platform
# needs that vanilla flatly lacks: a remote-admin surface. Its REST API is what
# core-server's activity probe polls for the live player list (idle-shutdown,
# the Avatars tab); vanilla's only admin channel is an interactive stdin
# console, which is useless from another container. Each TShock release is
# built against ONE exact Terraria version, so TSHOCK_VERSION and
# TERRARIA_COMPAT below move in lockstep — take both from the release name.
#
# Worlds live in /worlds (volume mount). TShock's own state (config.json,
# sqlite DB, logs) lives in /worlds/tshock — ON THE VOLUME — so users, groups,
# and bans survive container replacement.
#
# Build:
#   docker build -t cfg-server-terraria:local .
#
# Run (local test):
#   docker run --rm -p 7777:7777 -v /tmp/terraria-worlds:/worlds cfg-server-terraria:local
#
# CFG-hosted: core-server provisions one container per user installation via
# the Server Manager kind-registry (kinds/terraria.ts → services/terraria/launch.ts).

ARG TSHOCK_VERSION=6.1.0
ARG TERRARIA_COMPAT=1.4.5.6

FROM debian:bookworm-slim AS extract

ARG TSHOCK_VERSION
ARG TERRARIA_COMPAT
# TARGETARCH is amd64 in CI/prod; TShock also publishes linux-arm64, which
# makes native local verification possible on Apple-silicon dev machines.
ARG TARGETARCH

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build
# Release asset: a zip wrapping a tar (their packaging quirk — the inner tar
# keeps a "TShock-Beta-*" name even on stable releases, hence the glob).
RUN case "$TARGETARCH" in \
      arm64) TSHOCK_ARCH=linux-arm64 ;; \
      *)     TSHOCK_ARCH=linux-x64 ;; \
    esac && \
    curl -fsSLo tshock.zip "https://github.com/Pryaxis/TShock/releases/download/v${TSHOCK_VERSION}/TShock-${TSHOCK_VERSION}-for-Terraria-${TERRARIA_COMPAT}-${TSHOCK_ARCH}-Release.zip" && \
    unzip -q tshock.zip && \
    rm tshock.zip && \
    mkdir /opt/terraria && \
    tar -xf TShock-*-Release.tar -C /opt/terraria && \
    rm -f TShock-*-Release.tar /opt/terraria/TShock.Installer && \
    chmod +x /opt/terraria/TShock.Server

# ── Final runtime image ─────────────────────────────────────────────────────
# TShock 6's TShock.Server is a FRAMEWORK-DEPENDENT .NET 9 apphost (verified
# empirically — it aborts with "You must install .NET" on a bare Debian base),
# so the runtime comes from the official image. `runtime`, not `aspnet`:
# TShock's REST server is plain-BCL HTTP, no ASP.NET Core dependency.
FROM mcr.microsoft.com/dotnet/runtime:9.0-bookworm-slim

ARG TSHOCK_VERSION
ARG TERRARIA_COMPAT
LABEL org.opencontainers.image.title="cfg-server-terraria"
LABEL org.opencontainers.image.description="Crit-Fumble Terraria dedicated server container (TShock)"
LABEL org.opencontainers.image.source="https://github.com/Crit-Fumble/cfg-server-terraria"
LABEL org.opencontainers.image.licenses="AGPL-3.0-only"
LABEL org.opencontainers.image.version="${TSHOCK_VERSION}-terraria${TERRARIA_COMPAT}"

# tini reaps zombies and forwards SIGTERM so `docker stop` shuts the server
# cleanly (worlds are written on graceful exit; SIGKILL leaves dirty .wld
# files). The .NET base image already carries ICU/zlib/libstdc++.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && apt-get install -y --no-install-recommends \
      tini && \
    rm -rf /var/lib/apt/lists/* && \
    useradd --system --uid 1000 --user-group --no-create-home --shell /usr/sbin/nologin terraria && \
    # The engine writes favorites.json to $HOME/.local/share/Terraria on first
    # boot; with --no-create-home that throws a (caught but noisy)
    # DirectoryNotFoundException. Pre-create the tree so the write succeeds.
    mkdir -p /home/terraria/.local/share/Terraria && \
    chown -R terraria:terraria /home/terraria

COPY --from=extract /opt/terraria /opt/terraria
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# /worlds: saved worlds + TShock state (/worlds/tshock). Mount a
# per-installation host dir here.
# /opt/terraria: read-only binary tree; non-root user owns nothing in it.
RUN mkdir -p /worlds && chown -R terraria:terraria /worlds

USER terraria
WORKDIR /worlds

EXPOSE 7777/tcp
# TShock REST API — core-server's activity probe + Avatars roster read it.
# NEVER published to a host port: core-server dials the container by name over
# the shared docker network. The only gate is the derived token
# (TSHOCK_REST_TOKEN), so keeping this off the host firewall surface matters.
EXPOSE 7878/tcp

ENV TERRARIA_WORLD=cfg-world \
    TERRARIA_PORT=7777 \
    TERRARIA_MAXPLAYERS=8 \
    TERRARIA_DIFFICULTY=0 \
    TERRARIA_AUTOCREATE=2 \
    TERRARIA_MOTD="Crit-Fumble Terraria Server" \
    TSHOCK_REST_PORT=7878

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
