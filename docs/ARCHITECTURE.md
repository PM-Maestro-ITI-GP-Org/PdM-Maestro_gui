# Architecture

Maestro merges four Qt/QML applications into one window with a bottom tab bar,
without any of them ceasing to be an application in its own right.

## Shape

```
pdm_maestro (one process, one QApplication, one QQmlApplicationEngine)
│
├── shell/                    ApplicationWindow, TabBar, StackLayout
│                             Not a submodule -- nothing to run standalone.
│
├── core/                     submodule: pdm-core        [Phase 1]
│                             Theme, shared controls, MqttClient,
│                             MessageBus, AppRegistry
│
└── apps/                     submodules, one per tab
    ├── data_collection/      motor_recorder_gui   -> PdM.DataCollection
    ├── mlops/                (repo to be created) -> PdM.MlOps
    ├── ota/                  ota_update_gui       -> PdM.Ota
    └── agent/                (repo to be created) -> PdM.Agent
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

## How apps talk to each other

Through `PdM.Core`'s `MessageBus` — topic-based publish/subscribe over Qt
signals — and never by depending on each other directly. Data collection
finishes a recording and publishes it; ML/Ops subscribes. Neither repo names the
other, so both still build alone.

## What `pdm-core` has to hold

Larger than first estimated. With both repos checked out, these files exist in
`motor_recorder_gui` **and** `ota_update_gui`:

| File | Note |
|---|---|
| `Theme.qml` | the palette |
| `AppCard.qml` | |
| `FilledButton.qml` | |
| `StatusPill.qml` | |
| `mqttclient.{h,cpp}` | |

So Phase 1 is not just "hoist the palette" — it is a shared control set and the
MQTT client too. Two of these are already visibly diverging: the two
`CMakeLists.txt` files disagree about whether `QuickControls2` is a real link
dependency, and the copies will keep drifting until there is one of each.

**MQTT connection ownership** is the sharp edge. Both apps ship their own
`MqttClient` and both connect on their own. In one process, two connections with
a colliding client ID make the broker kick sessions in a loop, and it presents
as an intermittent network fault rather than as a bug in either app. Resolve
this in Phase 1, before either port — the answer decides whether `MqttClient`
becomes a shared singleton connection or stays per-app with distinct client IDs.

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
| 1 | `pdm-core`: Theme, MessageBus, AppRegistry | next |
| 2 | Port `motor_recorder_gui` -> tab 1 | |
| 3 | Port `ota_update_gui` -> tab 3 | |
| 4 | Build the ML/Ops GUI against the contract -> tab 2 | |
| 5 | AI agent -> tab 4 | |

## Branch policy

App repos are ported on a `feat/maestro-integration` branch, merged to `main`
once standalone still builds, then the branch is deleted. The submodule pins
commits on `main`. The changes are backward compatible by design, so there is
nothing to keep on a permanent side branch.

If a long-lived integration branch becomes unavoidable for some repo:
**merge `main` into it, never rebase.** A submodule pins a SHA, and rebasing
orphans the commit Maestro points at — a fresh clone then fails to check out the
submodule with a misleading "reference is not a tree".
