# cfg-server-terraria

Thin container around the official [Terraria dedicated server](https://terraria.org/server). Used by Crit-Fumble's Server Manager to host per-user Terraria instances under the `kind=terraria` adapter.

No mods, no plugins, no Steam dependency — just the upstream server binary, extracted onto `debian-slim`, run as a non-root user (`uid=1000`), with worlds living in a `/worlds` volume.

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

A user-supplied `/worlds/serverconfig.txt` (e.g. mounted in by core-server) takes precedence over the env-driven template.

## CFG-hosted usage

Core-server provisions one container per `UserAppInstallation` via the Server Manager kind-registry:

- adapter: `cfg-core-server/src/services/server-manager/kinds/terraria.ts`
- launcher: `cfg-core-server/src/services/terraria/launch.ts`
- volume: `/mnt/cfg_user_storage/users/<userId>/installations/<installationId>/data/` → `/worlds`

Billing tick (CT per uptime hour) is owned by the adapter, same shape as `kinds/foundryvtt.ts`.

## Build

```sh
docker build -t cfg-server-terraria:local .
# Pin to a specific Terraria version:
docker build --build-arg TERRARIA_VERSION=1456 -t cfg-server-terraria:1.4.5.6 .
```

CI publishes `ghcr.io/crit-fumble/cfg-server-terraria` on tagged releases (see `.github/workflows/build.yml`).

## License

AGPL-3.0-only. Terraria itself is © Re-Logic; the dedicated server binary is freely redistributable under [Re-Logic's terms](https://terraria.org/server). This repo contains only the thin packaging — none of Re-Logic's intellectual property is vendored.
