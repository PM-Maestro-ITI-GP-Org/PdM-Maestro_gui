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

Phase 3 done. **Data Collection and OTA Update are real tabs** —
`motor_recorder_gui` and `ota_update_gui` both run inside the shell, on
`pdm_app_core`'s palette, and both still build and run standalone from their own
repositories. ML/Ops and AI Agent are placeholders that report where they stand.

An app joins the build only once it carries a `pdm-app.cmake` marker, which the
port adds, so the configure output reports the migration state of all four:

```
-- PdM app 'data_collection': integrated as pdm_datacollection (PdM.DataCollection)
-- PdM app 'mlops': absent -- placeholder tab
-- PdM app 'ota': integrated as pdm_ota (PdM.Ota)
-- PdM app 'agent': absent -- placeholder tab
```

Phase 4 is next: building the ML/Ops GUI.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the merge works and why
- [docs/INTEGRATION_CONTRACT.md](docs/INTEGRATION_CONTRACT.md) — what an app repo
  must do to become a tab
