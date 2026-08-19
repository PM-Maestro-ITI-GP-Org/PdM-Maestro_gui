# Architecture

Maestro merges the toolchain's Qt/QML applications into one window with a bottom
tab bar, without any of them ceasing to be an application in its own right.
Four were planned; motor control was added later, and adding it needed no change
to the shell, the contract or core -- which is the clearest evidence the
arrangement works.

## Shape

```
pdm_maestro (one process, one QApplication, one QQmlApplicationEngine)
│
├── shell/                    ApplicationWindow, TabBar, StackLayout
│                             Not a submodule -- nothing to run standalone.
│
├── core/                     submodule: pdm_app_core
│                             Theme, MessageBus, AppRegistry, BrokerSettings
│
└── apps/                     submodules, one per tab
    ├── data_collection/      motor_recorder_gui     -> PdM.DataCollection
    ├── motor_control/        pdm_motor_control_gui  -> PdM.MotorControl
    ├── mlops/                pdm_mlops_gui          -> PdM.MlOps
    ├── ota/                  ota_update_gui         -> PdM.Ota
    └── agent/                (repo to be created)   -> PdM.Agent
```

Each app is a static library plus a QML module. Maestro links all of them; the
shell loads each app's root `Item` into a tab. See
[INTEGRATION_CONTRACT.md](INTEGRATION_CONTRACT.md) for what an app must do to
qualify.

## Why one process

The alternatives were considered and rejected:

- **Child processes with embedded windows** — breaks under Wayland, four event
  loops, no shared state, and not meaningfully "a single app".
- **Runtime-loaded QML plugins** — deferred, not rejected. It buys optional
  tabs, and costs deployment and debugging complexity that a laptop-only target
  does not justify yet.

## The three collisions

Everything structural in this repo exists to prevent one of these:

| Collision | Fix |
|---|---|
| Three `main()` functions | `if(PROJECT_IS_TOP_LEVEL)` guards each app's executable |
| Three `qrc:/main.qml` paths overwriting each other, silently | QML modules with distinct URIs |
| Three singletons named `Theme` | one `Theme` in `PdM.Core` |

A fourth, found while wiring core in: a static QML module needs **both** halves
linked (`pdm_core` *and* `pdm_coreplugin`) plus `Q_IMPORT_QML_PLUGIN` in
`main.cpp`. Missing the link fails loudly; missing the macro builds clean and
fails at run time with "Theme is not a type" from a file that plainly imports
`PdM.Core`.

## How apps talk to each other

Through `PdM.Core`'s `MessageBus` — topic-based publish/subscribe over Qt
signals — and never by depending on each other directly. Data collection
finishes a recording and publishes it; ML/Ops subscribes. Neither repo names the
other, so both still build alone.

## What `pdm_app_core` holds, and what it does not

Five files exist in both apps under the same names. They are not copies — they
have already diverged, in most cases past the point where merging them is worth
doing:

| File | data_collection | ota | Verdict |
|---|---|---|---|
| `Theme.qml` | 81 lines | 96 | **Hoisted.** Different token names *and* values; OTA's chosen as canonical |
| `AppCard.qml` | 55 | 67 | Later. Same shadow trick, different implementations |
| `FilledButton.qml` | 155 | 47 | Later. Four variants against one; different APIs |
| `StatusPill.qml` | 52 | 42 | Later. Different tone sets |
| `mqttclient.{h,cpp}` | 690 | 1421 | **Not merging.** See below |

Consolidating the three controls is best done once both apps are visible side by
side in the shell, not before.

### The MQTT client stays where it is

Two genuinely different clients: different topic trees (`guest/rpi5guest1/*`
against `hms/*`), different QoS, one running on a `QThread` worker and one not.
Merging them rewrites two working implementations for nothing the shell can see.
Only the broker *address* is shared, via `BrokerSettings` — both apps hardcode
`tcp://139.185.38.211:1883` in their own `.cpp` today, so pointing the system at
a different broker currently means editing two files in two repositories.

**The client-id collision is not a real problem.** Both apps already suffix an
epoch timestamp (`motor_gui_<ms>`, `ota_gui_<ms>`) and their topics do not
overlap, so two connections from one process are distinct at the broker.
`BrokerSettings::clientId()` exists to keep that true as apps three and four
arrive, not to fix something broken.

### The real hazard is the GUI thread

`motor_recorder_gui` calls `MQTTClient_connect` — Paho's *synchronous* API —
directly on the GUI thread, and polls with a yield timer. `ota_update_gui` runs
its client on a dedicated `QThread` worker.

Today that costs data collection a frozen window of up to its five-second
connect timeout, and nothing else. **Merged, it freezes all four tabs** —
including an OTA transfer in flight in another tab. This is the single most
important thing the Phase 2 port has to fix, and it is now rule 8 of the
contract.

## ML/Ops: a new GUI, not the AI repo as a submodule

The [AI repo](https://github.com/PM-Maestro-ITI-GP-Org/AI) (branch
`abdelrahman`) holds two different things and no Qt code: `mlops/` is a Python
training pipeline with DVC pointing at Backblaze S3, and `motor_fault_cpp_v2/`
is a C++ inference implementation.

It is **not** a Maestro submodule. The decisive reason is in its CMake:

```cmake
set(TFLITE_SRC_DIR "$ENV{HOME}/tensorflow")
set(TFLITE_BUILD_DIR "$ENV{HOME}/tflite_build")
```

A hand-built TensorFlow Lite in a developer's home directory. Submodule that
into Maestro and everyone who builds the shell needs a built TFLite or nothing
compiles — including the OTA and data-collection tabs, which have no interest in
ML at all.

So `pdm_mlops_gui` is a new Qt repo written against the contract, and it reads
the pipeline's own verdict: `mlops/gate.py` already checks the model against the
thresholds in `config/pipeline.yaml` and writes `model_out/metrics.json`. The tab
parses and watches that file, and re-checks nothing — a second opinion in the GUI
could disagree with the one CI releases on. The single action it offers is
`python3 -m mlops.gate`, run out of process.

If in-app live inference is wanted later, `motor_fault_cpp_v2` gets extracted
into its own repo and becomes a submodule *of `pdm_mlops_gui`*, behind an
optional CMake flag.

That rests on a rule worth keeping: **Maestro's submodules are exactly
`pdm_app_core` plus the four app repos. Anything an app needs, that app pulls in
itself.** It stops one app's build requirements becoming the whole shell's.

## Tabs are kept alive

The `Loader` for each page latches on at first visit and never unloads. Binding
`active` to "is the current tab" would tear down an in-progress recording or a
half-finished OTA transfer every time the user looked at another tab. Visited
tabs hold their memory; that is the intended trade.

## Toolchain

Qt **6.10.3** (`~/Qt/6.10.3/gcc_64`), CMake **3.21+**, C++17, desktop Linux only.

The system Qt is 6.2.4 and is below the floor — `qt_add_qml_module` maturity and
`engine.loadFromModule` want 6.5+. Use the preset:

```bash
cmake --preset dev && cmake --build build/dev -j$(nproc)
```

Maestro links `Qt6::Widgets` because `motor_recorder_gui` builds against
`QApplication` today. The application object is process-wide, so the shell must
construct the widest one any tab needs. Dropping to `QGuiApplication` is a later
cleanup, once every app is known not to want Widgets.

## Phases

| Phase | Scope | State |
|---|---|---|
| 0 | Maestro repo, shell, four placeholder tabs | **done** |
| 1 | `pdm_app_core`: Theme, MessageBus, AppRegistry, BrokerSettings | **done** |
| 2 | Port `motor_recorder_gui` -> tab 1 | **done** |
| 3 | Port `ota_update_gui` -> tab 3 | **done** |
| 4 | Build the ML/Ops GUI against the contract -> tab 2 | **done** |
| 5 | AI agent -> tab 5 | next |
| M0-M1 | Motor control: board link, state machine, emergency stop | **done** |
| M2-M6 | Motor control: scenario grid, run-and-record, fetch, wizard, series | |

## Branch policy

App repos are ported on a `feat/maestro-integration` branch. **`main` is not to
be touched** — the submodules pin commits on the integration branch, and
`.gitmodules` names that branch so `git submodule update --remote` follows it.

The ports are backward compatible by design, so merging to `main` would be safe
whenever the owner of each repo wants it; that call is not Maestro's to make.
Until then the branches are long-lived, which makes the rule below apply.

If a long-lived integration branch becomes unavoidable for some repo:
**merge `main` into it, never rebase.** A submodule pins a SHA, and rebasing
orphans the commit Maestro points at — a fresh clone then fails to check out the
submodule with a misleading "reference is not a tree".
