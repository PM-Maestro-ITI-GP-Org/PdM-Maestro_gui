# PdM Maestro

One window over the tools of the predictive-maintenance toolchain — motor
rig control, data collection, ML/Ops, OTA update, and (eventually) an AI
agent — with a tab per app along the bottom.

Each app remains its own repository that builds and runs on its own. Maestro
pulls them in as submodules and merges them into a single process.

**New to this project? Start with [CLAUDE.md](CLAUDE.md)** — the repo map,
branch policy, build instructions, and current state in one place. This
README is the short version.

## Build

The system Qt (6.2.4) is below this project's floor, so use the preset:

```bash
cmake --preset dev
cmake --build build/dev -j$(nproc)
./build/dev/bin/pdm_maestro
```

Requires Qt 6.10.3 at `~/Qt/6.10.3/gcc_64` and CMake 3.21+, including the
**Qt Serial Port** module — it is not part of a default Qt install, and the
motor control tab needs it. Add it through the Qt Maintenance Tool under
Qt 6.10.3 → Additional Libraries.

## Clone

```bash
git clone --recurse-submodules git@github.com:PM-Maestro-ITI-GP-Org/PdM-Maestro_gui.git
```

Already cloned without it:

```bash
git submodule update --init --recursive
```

## State

**Four of the five tabs are real** — Data Collection, Motor Control, ML/Ops and
OTA Update all run inside the shell on `pdm_app_core`'s palette, and each still
builds and runs standalone from its own repository. AI Agent is a placeholder
that reports where it stands.

An app joins the build only once it carries a `pdm-app.cmake` marker, which the
port adds, so the configure output reports the migration state of all four:

```
-- PdM app 'data_collection': integrated as pdm_datacollection (PdM.DataCollection)
-- PdM app 'motor_control': integrated as pdm_motorcontrol (PdM.MotorControl)
-- PdM app 'mlops': integrated as pdm_mlops (PdM.MlOps)
-- PdM app 'ota': integrated as pdm_ota (PdM.Ota)
-- PdM app 'agent': absent -- placeholder tab
```

The AI Agent tab is next, and last — and is not yet scoped. See
[docs/STATUS.md](docs/STATUS.md) before starting it.

## Documentation

- [CLAUDE.md](CLAUDE.md) — orientation, repo map, branch policy, gotchas
- [docs/STATUS.md](docs/STATUS.md) — the detailed log: every phase, every
  bug found and fixed, what's still open
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the merge works and why
- [docs/INTEGRATION_CONTRACT.md](docs/INTEGRATION_CONTRACT.md) — what an app repo
  must do to become a tab
