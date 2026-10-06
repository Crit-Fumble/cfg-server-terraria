# cfg-server-terraria

Thin container around the official [Terraria dedicated server](https://terraria.org/server). Used by Crit-Fumble's Server Manager to host per-user Terraria instances under the `kind=terraria` adapter.

The image runs TShock (Pryaxis), which wraps the official Terraria server engine 1:1 for gameplay and adds the REST admin API
core-server's activity probe reads. No Steam dependency; a .NET 9 `bookworm-slim` base running as non-root `uid=1000`, with worlds and
TShock's own state (`/worlds/tshock`: config, sqlite DB, logs) in the `/worlds` volume.

## Run standalone

```sh
docker run --rm -p 7777:7777 -v $(pwd)/worlds:/worlds \
  ghcr.io/crit-fumble/cfg-server-terraria:latest
```

First boot auto-creates `cfg-world.wld` (medium classic) if `/worlds/` is empty. The world saves on every clean exit — `docker stop` forwards SIGTERM via tini so saves complete.

## Config knobs (env vars)

| var | default | meaning |
|---|---|---|
| `TERRARIA_WORLD` | `cfg-world` | world file basename |
| `TERRARIA_PORT` | `7777` | listen port |
| `TERRARIA_MAXPLAYERS` | `8` | player cap |
| `TERRARIA_DIFFICULTY` | `0` | 0 classic / 1 expert / 2 master / 3 journey |
| `TERRARIA_AUTOCREATE` | `2` | 1 small / 2 medium / 3 large; first-boot only |
| `TERRARIA_PASSWORD` | _(empty)_ | server password |
| `TERRARIA_MOTD` | _Crit-Fumble Terraria Server_ | message of the day |
| `TERRARIA_SEED` | _(empty, random)_ | world seed |

`/worlds/serverconfig.txt` is rewritten from these env vars on every boot, for inspection and manual recovery only: the server runs on
CLI flags (Terraria 1.4.5+ silently ignores `autocreate` when it reads a config file), so editing or mounting that file changes nothing.
TShock's own settings live in `/worlds/tshock/config.json`, which the entrypoint seeds only when absent (REST API on only if
`TSHOCK_REST_TOKEN` is set), so hand edits there persist.

## CFG-hosted usage

> ℹ️ **`cfg-core-server` is a private CFG repo.** The paths below are named for orientation —
> they are not links you can open. **Nothing in this repo depends on them:** the container runs
> standalone with the `docker run` above, and the CFG integration is one consumer of it, not a
> requirement.

Core-server provisions one container per `UserAppInstallation` via the Server Manager kind-registry:

- adapter: `cfg-core-server/src/services/server-manager/kinds/terraria.ts`
- launcher: `cfg-core-server/src/services/terraria/launch.ts`
- volume: `/mnt/cfg_user_storage/users/<userId>/installations/<installationId>/data/` → `/worlds`

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
