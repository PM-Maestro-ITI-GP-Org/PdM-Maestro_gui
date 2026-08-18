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

Phase 2 done. **Data Collection is a real tab** — `motor_recorder_gui` runs
inside the shell, on `pdm_app_core`'s palette, and still builds and runs
standalone from its own repository. The other three tabs are placeholders that
report where their app stands.

An app joins the build only once it carries a `pdm-app.cmake` marker, which the
port adds, so the configure output reports the migration state of all four:

```
-- PdM app 'data_collection': integrated as pdm_datacollection (PdM.DataCollection)
-- PdM app 'mlops': absent -- placeholder tab
-- PdM app 'ota': checked out, not yet ported -- placeholder tab
-- PdM app 'agent': absent -- placeholder tab
```

Phase 3 is next: porting `ota_update_gui`.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the merge works and why
- [docs/INTEGRATION_CONTRACT.md](docs/INTEGRATION_CONTRACT.md) — what an app repo
  must do to become a tab
