# cfg-server-terraria

Thin container around the official [Terraria dedicated server](https://terraria.org/server). Used by Crit-Fumble's Server Manager to host per-user Terraria instances under the `kind=terraria` adapter.

The image runs TShock (Pryaxis), which wraps the official Terraria server engine 1:1 for gameplay and adds the REST admin API
core-server's activity probe reads. No Steam dependency; it runs as non-root `uid=1000` (or any uid given with `--user`), with worlds and
TShock's own state (`/worlds/tshock`: config, sqlite DB, logs) in the `/worlds` volume.

## Run standalone

```sh
docker run --rm -p 7777:7777 -v $(pwd)/worlds:/worlds \
  ghcr.io/crit-fumble/cfg-server-terraria:latest
```

First boot auto-creates `cfg-world.wld` (medium classic) if `/worlds/` is empty. `docker stop` saves the world before the server exits
(`entrypoint.sh` says how: TShock does not save on SIGTERM by itself).

## Config knobs (env vars)

| var | default | meaning |
|---|---|---|
| `TERRARIA_WORLD` | `cfg-world` | world file basename |
| `TERRARIA_PORT` | `7777` | listen port |
| `TERRARIA_MAXPLAYERS` | `8` | player cap |
| `TERRARIA_DIFFICULTY` | `0` | 0 classic / 1 expert / 2 master / 3 journey |
| `TERRARIA_AUTOCREATE` | `2` | 1 small / 2 medium / 3 large; first-boot only |
| `TERRARIA_WORLDEVIL` | `-1` | -1 random / 0 corruption / 1 crimson; first-boot only |
| `TERRARIA_PASSWORD` | _(empty)_ | server password |
| `TERRARIA_MOTD` | _Crit-Fumble Terraria Server_ | message of the day |
| `TERRARIA_SEED` | _(empty, random)_ | world seed |

`/worlds/serverconfig.txt` is rewritten from these env vars on every boot, for inspection and manual recovery only: the server runs on
CLI flags (Terraria 1.4.5+ silently ignores `autocreate` when it reads a config file), so editing or mounting that file changes nothing.
TShock's own settings live in `/worlds/tshock/config.json`, which the entrypoint seeds only when absent (REST API on only if
`TSHOCK_REST_TOKEN` is set), so hand edits there persist.

## CFG-hosted usage

Crit-Fumble hosts one container per member's server through its own (private) platform. Nothing in this
repo depends on that: the container runs standalone with the `docker run` above, and the platform is one
consumer of it, mounting a member's server data at `/worlds`.

## Build

```sh
docker build -t cfg-server-terraria:local .
# Build a different upstream: TShock is compiled against ONE exact Terraria
# version, so these two move together — take both from the TShock release name.
docker build --build-arg TSHOCK_VERSION=6.1.0 --build-arg TERRARIA_COMPAT=1.4.5.6 \
  -t cfg-server-terraria:6.1.0 .
```

CI publishes `ghcr.io/crit-fumble/cfg-server-terraria` on tagged releases (see `.github/workflows/build.yml`).

## License

AGPL-3.0-only. Terraria itself is © Re-Logic; the dedicated server binary is freely redistributable under [Re-Logic's terms](https://terraria.org/server). This repo contains only the thin packaging — none of Re-Logic's intellectual property is vendored.
