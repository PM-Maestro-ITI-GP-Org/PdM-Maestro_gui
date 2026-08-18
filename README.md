# PdM Maestro

One window over the four tools of the predictive-maintenance toolchain — data
collection, ML/Ops, OTA update, and an AI agent — with a tab per app along the
bottom.

Each app remains its own repository that builds and runs on its own. Maestro
pulls them in as submodules and merges them into a single process.

## Build

The system Qt (6.2.4) is below this project's floor, so use the preset:

```bash
cmake --preset dev
cmake --build build/dev -j$(nproc)
./build/dev/bin/pdm_maestro
```

Requires Qt 6.10.3 at `~/Qt/6.10.3/gcc_64` and CMake 3.21+.

## Clone

```bash
git clone --recurse-submodules git@github.com:PM-Maestro-ITI-GP-Org/pdm-maestro.git
```

Already cloned without it:

```bash
git submodule update --init --recursive
```

## State

Phase 0. The shell runs with four tabs, every one a placeholder that reports
where its app stands. `motor_recorder_gui` and `ota_update_gui` are checked out
under `apps/` but are not compiled in yet — an app joins the build only once it
carries a `pdm-app.cmake` marker, which the port adds. The configure output
reports the migration state of all four.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the merge works and why
- [docs/INTEGRATION_CONTRACT.md](docs/INTEGRATION_CONTRACT.md) — what an app repo
  must do to become a tab
