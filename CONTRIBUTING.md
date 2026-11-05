# Contributing to cfg-server-terraria

This repo is a thin container around TShock (Pryaxis), which wraps the official
Terraria dedicated server engine 1:1 — a `Dockerfile`, an `entrypoint.sh`, and
one boot test. There is no Node toolchain; **Docker is the only prerequisite**.

## Build & run locally

```bash
docker build -t cfg-server-terraria:local .
docker run --rm -p 7777:7777 -v "$PWD/worlds:/worlds" cfg-server-terraria:local
```

The README documents the env-var config knobs and the CFG-hosted usage. When
changing `entrypoint.sh`, run `test/boot.sh` (CI runs it before every publish):
it boots a fresh container per world-evil value and proves each one listens,
saves on `docker stop` and exits 0. Verify by hand what it does not cover:
`/worlds/tshock/config.json` is seeded only when absent (so a user's hand edits
survive a restart).

## Commit messages & PRs

Use [Conventional Commits](https://www.conventionalcommits.org/)
(`feat`, `fix`, `chore`, `docs`, `ci`, `build`). Fork, branch from `next` (the release-candidate branch;
`main` is released truth and only ever fast-forwarded to),
describe how you tested the container, and explain the *why* in the PR
description.

## License

Contributions are accepted under [AGPL-3.0-only](LICENSE). This repo must stay
thin packaging — never vendor any of Re-Logic's intellectual property.
