# PdM Maestro — orientation for whoever (or whatever) picks this up next

Read this file first. It is the map; [docs/STATUS.md](docs/STATUS.md) is the
detailed log of how each piece got the way it is, and is the file to read
before touching anything specific.

## What this is

One Qt/QML application — a bottom tab bar over five tools for a predictive-
maintenance motor rig. Each tab is a **separate git repository**, pulled in as
a submodule and merged into one process at build time. Every app repo still
builds and runs completely on its own; nothing about being part of Maestro is
required to use it standalone.

```
pdm_maestro (one process, one QApplication, one QQmlApplicationEngine)
│
├── shell/          the ApplicationWindow, TabBar, StackLayout — not a
│                    submodule, nothing to run standalone
│
├── core/            submodule: pdm_app_core
│                    Theme, MessageBus, AppRegistry, BrokerSettings, SafetyStop
│
└── apps/            submodules, one per tab, IN TAB ORDER
    ├── motor_control/    pdm_motor_control_gui  → PdM.MotorControl
    ├── data_collection/  motor_recorder_gui      → PdM.DataCollection
    ├── mlops/            pdm_mlops_gui           → PdM.MlOps
    ├── ota/              ota_update_gui          → PdM.Ota
    └── agent/            (no repo yet)           → PdM.Agent   [placeholder]
```

**Why this structure exists, and the collisions it prevents, are explained in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Read it before changing how
apps are wired together.** The short version: three apps sharing one process
would collide on three `main()` functions, three `qrc:/main.qml` paths, and
three `Theme` singletons. `PROJECT_IS_TOP_LEVEL` guards, QML module URIs, and
one shared `Theme` in core are the fixes, respectively.

**What an app repo has to do to become a tab is
[docs/INTEGRATION_CONTRACT.md](docs/INTEGRATION_CONTRACT.md).** Read it before
porting a fifth or sixth app, or before believing a claim like "this app
follows the contract" without checking.

## The seven repositories

| Repo | URL | Branch here | Role |
|---|---|---|---|
| **PdM-Maestro_gui** | `PM-Maestro-ITI-GP-Org/PdM-Maestro_gui` | `main` | This repo. The shell + submodule pins. |
| **pdm_app_core** | `PM-Maestro-ITI-GP-Org/pdm_app_core` | `main` | Shared palette, message bus, app registry, broker settings, safety stop. |
| **pdm_motor_control_gui** | `PM-Maestro-ITI-GP-Org/pdm_motor_control_gui` | `main` | The rig control tab. New repo, written against the contract from the start. |
| **pdm_mlops_gui** | `PM-Maestro-ITI-GP-Org/pdm_mlops_gui` | `main` | ML/Ops tab. New repo, written against the contract from the start. |
| **motor_recorder_gui** | `PM-Maestro-ITI-GP-Org/motor_recorder_gui` | `feat/maestro-integration` | Data Collection tab. **Ported**, not new — see branch policy below. |
| **ota_update_gui** | `PM-Maestro-ITI-GP-Org/ota_update_gui` | `feat/maestro-integration` | OTA Update tab. **Ported**, not new — see branch policy below. |
| **motor_control_node** | `PM-Maestro-ITI-GP-Org/motor_control_node` | `feat/estop-2500ms` | The ESP32 rig firmware + protocol docs. Not a Maestro submodule — the GUI talks to it over USB serial. |

`motor_control_node` lives at `~/ITI_Files/GP/dataCollection/esp_dac`, outside
this repo tree, alongside a **separate, untouched clone of
`motor_recorder_gui` on `main`** at
`~/ITI_Files/GP/dataCollection/motor_recorder_gui` — do not confuse that
standalone checkout with the submodule at `apps/data_collection`, they are
independent working trees of the same remote.

## Branch policy — this is not optional

**Never commit to `main` on `motor_recorder_gui`, `ota_update_gui`, or
`motor_control_node`.** All integration work happens on
`feat/maestro-integration` (app repos) or `feat/estop-2500ms` (firmware),
merged from `main` when it moves, never rebased — a submodule pins a commit
SHA, and rebasing orphans it. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#branch-policy).

`pdm_app_core`, `pdm_motor_control_gui`, and `pdm_mlops_gui` are new repos
with no independent `main` to protect; work there happens on `main` directly.

## Build

```bash
git clone --recurse-submodules git@github.com:PM-Maestro-ITI-GP-Org/PdM-Maestro_gui.git
cd PdM-Maestro_gui
cmake --preset dev
cmake --build build/dev -j$(nproc)
./build/dev/bin/pdm_maestro
```

Needs **Qt 6.10.3** at `~/Qt/6.10.3/gcc_64` (system Qt is 6.2.4, below the 6.5
floor `qt_add_qml_module`/`loadFromModule` need — the preset points at the
right one) and the **Qt Serial Port** module, added via the Qt Maintenance
Tool (`~/Qt/MaintenanceTool` → Qt 6.10.3 → Additional Libraries), since it is
not part of a default install and the motor control tab links it.

Each app also builds completely standalone from its own checkout — see each
repo's own README for the exact command.

## Current state — read docs/STATUS.md for the detail behind every line

| Tab | State |
|---|---|
| Motor Control | **Functionally complete** (M0–M6, M3.5). Verified against real hardware: scenario runs, emergency stop at the new 2.5 s ramp, upload+replay, the fetch-and-clear cycle (310 MB, byte-verified, then deleted). **Not yet verified live:** a full series run end-to-end on the bench. |
| Data Collection | Ported to the contract (Phase 2 of the original 5-phase plan). MQTT connect moved off the GUI thread. Subscribes to `recording.start`/`recording.stop` on the bus. |
| ML/Ops | Written against the contract. Reads `mlops/gate.py`'s own verdict from `model_out/metrics.json`; forms no second opinion. **Never tested against a real pipeline run** — only a hand-built fixture matching the schema. |
| OTA Update | Ported to the contract, merged forward with six commits from upstream `main`. |
| AI Agent | **Placeholder only.** Never scoped. See "What's actually left" below. |

Firmware: `ESTOP_MS` changed from 2000 to 2500 on `motor_control_node`,
flashed to the bench board, verified live (`*** EMERGENCY STOP: ... over 2.5
s ***`). Rig still reports `NOT YET CALIBRATED` — full scale may be
unreachable until `v` is run at the bench. This has been true throughout and
was never addressed; do not assume it has been fixed.

## What's actually left

1. **A live series run**, start to finish, on the bench. The queue logic has
   83 passing unit tests covering the tricky parts (naming, abort semantics,
   resume, pause) but has never been watched running for real.
2. **The AI Agent tab.** Completely unscoped — no code, no repo. Before
   building anything, read `GP/ai/pm_readme.md` and the two
   `HypridDesign`/`HypridAdabtiveDesign` docs beside it. What they describe
   (Layer 5) is a **voice-assistant-style Q&A layer** over the ML outputs —
   "how much life is left in the motor?" → a spoken answer built from a
   number the models already produced — not an LLM-with-tools agent, and the
   two should not be conflated without asking which one is actually wanted.
   Considerations raised but never resolved with the user, worth re-raising
   before starting:
     - **Deterministic first, LLM optional.** Compute the answer from real
       model output; use an LLM only to phrase the sentence, with a
       template fallback when there's no API key. A demo that depends on a
       network call for its main feature is a liability in front of a
       committee.
     - **Bounded vs. live scope.** "Bounded" = answers from gate reports,
       recordings, and system state already sitting in the other tabs — no
       new dependency. "Live" = real-time fault/RUL inference, which pulls
       in `AI/motor_fault_cpp_v2` and its hand-built TensorFlow Lite — the
       exact dependency `pdm_mlops_gui` was deliberately built to avoid
       needing. Bounded first, live behind an optional flag second, was the
       standing recommendation.
     - **Read-only, propose-only.** OTA can kill hypervisor guests and push
       updates over MQTT. The agent should never issue that command itself —
       propose it, put a button next to the proposal, let a human click it.
     - **TTS is unresolved.** The design doc's voice output may have been
       scoped for an RPi/IVI target, not necessarily wanted on the laptop
       build this project actually targets. Ask before adding the
       dependency.
3. **Calibrate the rig** (`v`, ~20 s) before recording anything meant to be
   kept — every session so far has run against uncalibrated pots.
4. **`motor_recorder_gui`'s `MQTTClient_disconnect` still blocks the GUI
   thread** for up to 1 s in `teardownClient()`. Flagged, not fixed — smaller
   than the connect-side fix already made, but the same class of bug.
5. **`RUN_MIN` in `esp_dac`'s firmware is 100, while the comment beside it
   and the repo's own README both describe 132 as settled.** Found
   2026-08-20 fact-checking this document, confirmed against the actual
   flashed firmware, not fixed — not this session's call to make. Full
   detail in [docs/STATUS.md](docs/STATUS.md). Do not trust the README's
   prose over the `.ino` source on this specific constant until someone
   reconciles them.
6. Merging `feat/maestro-integration` back to `main` on the two ported app
   repos, and `feat/estop-2500ms` back to `main` on the firmware, is a call
   for whoever owns those repos to make — the changes are backward compatible
   by design, but the merge itself was never requested.

## Rig access

Getting recordings off the QNX guest needs a manually-opened, multiplexed SSH
session — key auth is impossible on that hardware (read-only boot image).
Full explanation, the exact commands, and the failure modes are in
[pdm_motor_control_gui/docs/RIG_ACCESS.md](../pdm_motor_control_gui/docs/RIG_ACCESS.md)
(relative to a sibling checkout) or `docs/RIG_ACCESS.md` inside that repo.

```bash
ssh -M -S ~/.ssh/rig.sock -o ControlPersist=8h -J root@10.145.0.81 root@10.0.0.2 "echo rig session open"
```

## Gotchas worth knowing before you rediscover them

- **Linux truncates process names at 15 characters.** `pgrep -x
  motor_control_gui` matches nothing; use `motor_control_g` or match on the
  full command line.
- **A static QML module needs both halves linked** — the library target and
  the `*plugin` target — plus `Q_IMPORT_QML_PLUGIN` in whichever `main.cpp`
  loads it. Missing the link fails at link time (loud); missing the macro
  builds clean and fails at runtime with "X is not a type" (quiet).
- **`StackLayout` sizes to its tallest child**, not its current one. Bit both
  the record wizard and the replay dialog.
- **Qt signal emission is synchronous.** The custom-session replay bug (fixed
  2026-08-20) was exactly this: a signal was emitted one line before the
  state its own listener depended on had been set.
- **Test harnesses that talk to the real app's QSettings must use a
  different `applicationName`.** `series_probe`'s first version didn't, and
  it silently overwrote the operator's live series settings on every run.
