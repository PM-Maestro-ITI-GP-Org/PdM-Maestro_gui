# Status — the detailed log

[CLAUDE.md](../CLAUDE.md) is the map. This is what's actually happened, phase
by phase, repo by repo, with enough detail that a real bug fix or a real
design decision doesn't have to be rediscovered. Written 2026-08-20 as a
handoff snapshot — treat every claim here as true as of that date and verify
against the code before relying on it for anything that matters.

## Maestro itself (PdM-Maestro_gui)

Built in five phases, all done:

- **Phase 0** — the shell, `pdm-app.cmake` markers so an app joins the build
  only once it declares itself ready, placeholder tabs.
- **Phase 1** — `pdm_app_core`: `Theme` (adopted from `ota_update_gui`'s
  palette, chosen as canonical — the more developed of the two), `MessageBus`,
  `AppRegistry`, `BrokerSettings`.
- **Phase 2** — ported `motor_recorder_gui`. The biggest rename sweep (its
  own `Theme.qml` tokens didn't match OTA's), and the phase that found the
  MQTT-connect-blocks-the-GUI-thread bug (see below).
- **Phase 3** — ported `ota_update_gui`, merged six commits forward from
  upstream `main` in the process (`feat/maestro-integration` was already
  behind by then).
- **Phase 4** — `pdm_mlops_gui`, new, written against the contract. Reads
  `mlops/gate.py`'s own verdict rather than re-implementing the thresholds.
- **Motor control** — added later, as a fifth tab, after the original
  four-tab plan. Slotting it in needed **zero changes** to the shell, the
  contract, or core — the strongest evidence the architecture actually works
  the way it was supposed to.
- **AI Agent** — never scoped past "lowest priority, reserve the tab." Still
  just that: a placeholder.

### The MQTT-blocks-GUI-thread bug (Phase 2)

`motor_recorder_gui` called Paho's *synchronous* `MQTTClient_connect`
directly on the GUI thread. Standalone, this cost a frozen window for up to
its 5 s connect timeout and nothing else. Merged into Maestro, one shared
event loop means that same call freezes **all tabs**, including an OTA
transfer running in a different one. Fixed by moving the connect call onto a
`QThread` worker, with the handle still created/destroyed on the GUI thread
and the two sides guarded so they never touch it concurrently. Verified both
ways: against the real broker, and against a black-holed IP (window stayed
responsive through the full 5 s stall; reconnect backoff worked with no
overlapping attempts).

This is now **rule 8 of `docs/INTEGRATION_CONTRACT.md`**: no synchronous
network or file I/O on the GUI thread. `MQTTClient_disconnect` in the same
file's `teardownClient()` still blocks for up to 1 s and was never fixed —
smaller, same class of bug, flagged as open work.

### The tab-bar underline bug

The Material style's `TabBar` draws its active-tab underline as a `ListView`
highlight that slides between items — driven by different machinery than the
label colors (which read `currentIndex` directly). At startup these
disagreed: the label for tab 0 was correctly bold/colored while the
underline sat under tab 2. Fixed by replacing the shared highlight with a
per-button underline bound to the same `current` property the label uses, so
the two literally cannot disagree.

### Tab order

Registration order in `shell/main.cpp` is tab order (`AppRegistry`'s design:
"tab order is registration order"). As of 2026-08-20 the order is **Motor
Control, Data Collection, ML/Ops, OTA Update, AI Agent** — Motor Control was
moved to first/default on request.

## pdm_app_core

Five singletons, each a `static instance()` + `create(QQmlEngine*,
QJSEngine*)` pair — the pattern every other singleton in this codebase
follows:

- **`Theme`** — the shared palette (OTA's values).
- **`MessageBus`** — topic-string publish/subscribe. First real user was
  Motor Control's M3 (recording start/stop across the bus to Data
  Collection); before that it sat unused since Phase 1.
- **`AppRegistry`** — the tab list as a `QAbstractListModel`; an app calls
  `setPage(id, url)` from its own library to turn its placeholder into a real
  tab.
- **`BrokerSettings`** — one shared MQTT broker address (both `motor_
  recorder_gui` and `ota_update_gui` used to hardcode
  `tcp://139.185.38.211:1883` independently) and a `clientId(appId)` helper
  (not actually load-bearing — both apps already suffix a timestamp and don't
  collide, but it's there for the next app that might not).
- **`SafetyStop`** — added when Motor Control needed a stop reachable from
  every tab, not just its own. An app `arm(summary)`/`disarm()`s it; the
  shell renders a red strip above the tab bar for as long as it's armed,
  regardless of which tab is showing. This is what makes the emergency stop
  visible even while looking at, say, OTA Update, while the motor is still
  turning.

A real bug was found writing `pdm_app_core`'s own smoke test: a `QObject`
connection using the application object as context, capturing two locals by
reference in a lambda, outlived the locals' stack frame — harmless until a
second message was published, then a use-after-free. Fixed by using a
narrower-scoped `QObject` as the connection context.

**14 checks**, run via `ctest` in the repo's own `build/`.

## motor_recorder_gui (Data Collection tab)

On `feat/maestro-integration`, not `main`. The port: split into a library +
`PdM.DataCollection` QML module behind `PROJECT_IS_TOP_LEVEL`, `main.qml` →
`DataCollectionPage.qml` (an `Item`, window-only bits moved to a thin
standalone `Main.qml`), local `Theme.qml` deleted in favor of core's, MQTT
connect moved off the GUI thread (see above).

**M3 (Motor Control's requirement):** subscribes to `recording.start` /
`recording.stop` on `MessageBus`, so a scenario run in the Motor Control tab
can start and stop a recording here without either repo naming the other.

## ota_update_gui (OTA Update tab)

Also on `feat/maestro-integration`. Same shape of port as Data Collection.
Palette already matched core's (it *was* core's source), so this port was a
smaller diff than Data Collection's. Later merged six commits forward from
upstream `main`: fetch batching, guest browsing fixes, a Send-to-guest
stepper, monitor display fixes, and — notably — a maximized-not-fullscreen
window fix that had to be re-homed from the (now-deleted) `ApplicationWindow`
into the new standalone-only `Main.qml`, since a tab has no window to
maximize.

## pdm_mlops_gui (ML/Ops tab)

New repo, `main`. Deliberately **not** a submodule of the `AI` repo — that
repo's `motor_fault_cpp_v2` needs a hand-built TensorFlow Lite pinned to
`$HOME/tensorflow`, which would make every Maestro build (including the OTA
and Data Collection tabs, which have no interest in ML) depend on it.
Instead this tab parses and watches `model_out/metrics.json`, the file
`mlops/gate.py` in the `AI` repo already writes, and re-implements none of
the pass/fail logic — a second opinion here could disagree with the one CI
actually releases on.

**Never run against a real pipeline output** — only against a hand-built
JSON fixture matching the schema `gate.py` writes. If the real pipeline's
output ever disagrees with that schema, this tab has not seen it.

**The path it watches has since moved — found 2026-08-20 while scoping the
AI Agent tab, not fixed.** `MlOpsPage.qml` reads `model_out/metrics.json` and
runs `python3 -m mlops.gate`. In the `AI` repo, `gate.py` now lives at
`old_pipeline/mlops/gate.py`: the repo was restructured into `host_pipeline/`
(four notebooks — data building, anomaly, classification, RUL),
`rpi_pipeline/` (C++ inference) and `MLops/` (empty, with its README pointing
back at `old_pipeline/` for the previous DVC/CI setup). The checked-out branch
is `newPipeline_RUL_v1`, not the `abdelrahman` that `ARCHITECTURE.md` names,
and `MLops/README.md` states there is **no active CI** — the old workflow was
deleted because it pointed at paths that moved.

So everything above about this tab describes a pipeline layout that is no
longer the live one. Whether the tab should follow the new pipeline, or
whether `old_pipeline` is still what gets released, is a question for whoever
owns the `AI` repo — it is about intent, not a typo, and was not guessed at
here. Note also that `AI/README.md` says nothing under the new directories is
implemented while `AI/host_pipeline/README.md` says all four notebooks are;
both are current. See `apps/agent/docs/SCOPE.md` §5.

## motor_control_node (ESP32 firmware, repo name; folder name `esp_dac`)

Not a Maestro submodule — it's flashed hardware, and the GUI talks to it over
USB serial. Lives at `~/ITI_Files/GP/dataCollection/esp_dac`, with excellent
existing protocol/safety docs in `docs/`. On branch `feat/estop-2500ms`.

One change: `ESTOP_MS` 2000 → 2500 (a *duration*, not a rate — makes every
stop gentler, not just fast ones, since the ramp takes the same time
regardless of starting speed). Compiled, flashed to the bench board, and the
new ramp verified live in the board's own output:
`*** EMERGENCY STOP: 248 -> 93 over 2.5 s ***`. A pre-flash safety dump of
the sweep then in RAM was taken and verified byte-for-byte before flashing
(turned out unnecessary — the sweep survives in NVS across a reflash — but
worth doing given the alternative was unrecoverable).

Also committed: a new real sweep recorded during bench testing
(`sweeps/sweep_20260819_210049.{txt,csv}`).

**A live, currently-unresolved discrepancy, found 2026-08-20 while writing
this document — do not assume it is fixed just because the prose around it
sounds settled.** `drive_scenarios.ino` line 313:

```cpp
static const uint8_t RUN_MIN = 100;   // 1.71 V — ~109 rpm
```

**The comment is wrong for the value beside it.** `voltsFor(100)` is 1.294 V,
not 1.71 V — 1.71 V is `voltsFor(132)`. The top-level `README.md` (commit
`bee1120`, authored 2026-08-18, **not** part of this conversation's work)
rewrote the surrounding prose to describe 132 as the settled analysis floor
("`RUN_MIN` stays at 132 on purpose") without changing this line to match —
a partial edit, not a resolved question. `bee1120` is confirmed an ancestor
of the firmware actually flashed to the bench board (commit `d87708a`, the
2.5 s estop change), so **the board running right now enforces 100, not
132**, regardless of what the README says.

Consequences, checked rather than assumed: the ten scripted A–J scenarios
are unaffected — verified earlier that none of them ever commands below
code 132 regardless of where `RUN_MIN` is set. What *is* affected: a hand
sweep or a replay can legitimately produce codes in the 100–131 range (a
hand doesn't respect firmware constants), and `rpmFor()` extrapolates
linearly below its calibration point — a live reading in that range shows a
nonsensical negative rpm (the vendored `scenarios.json`'s
`band.run_min_rpm: -66` is this exact artifact). The firmware's own comment
at the same site also warns that `scenStats()` counts a held segment as
cruise whenever its code is `>= RUN_MIN`, so a segment held in 100–131 would
be miscounted as cruising in the dataset statistics — not triggered by the
built-in tables, but real for anything hand-recorded in that range.

**Not fixed here.** `RUN_MIN`/`RUN_MAX` are explicitly commented in the same
file as "properties of the inverter, not knobs to tune" and changing one
"starts a new dataset" — a call for whoever owns `esp_dac`, not something to
silently correct while writing documentation.

**Rig calibration:** every session so far has run against pots that report
`NOT YET CALIBRATED`. `v` (~20 s, output held at STOP throughout) was never
run. Do this before recording anything meant to be kept.

## pdm_motor_control_gui (Motor Control tab) — the newest and largest piece

New repo, `main`, written against the contract from the start. Built in
seven phases (M0–M6 plus M3.5, numbered out of order because M3.5 was
inserted between M3 and M4 after the fact):

| Phase | What | Bench-verified? |
|---|---|---|
| M0 | Repo, core submodule, CMake, tab, `scenarios.json` vendored | — |
| M1 | Serial worker (own `QThread`), board-state parser, always-reachable stop | ✅ |
| M2 | A–J scenario grid, run flow with confirmation | ✅ (upload/replay only; a scripted-scenario RUN specifically has not been separately re-confirmed since M1, though the parser has) |
| M3 | Run-only vs. run-and-record, via `MessageBus` | ✅ |
| M3.5 | Fetch-and-clear from the QNX guest, over a multiplexed SSH session | ✅ — 310 MB fetched, byte-verified, then deleted, on real hardware |
| M4 | Custom-session record wizard | ✅ — a real 12 s sweep recorded on the bench |
| M5 | Series runner: queue, per-series cooling gap, pause, resume | ⚠️ unit-tested (83 checks) but **never run live end to end** |
| M6 | Upload + replay a stored sweep | ✅ — see the 2026-08-20 bug below |

**83 checks**, `ctest` in the repo's own `build/`. Three extra probe
binaries exist for bench work beyond the GUI itself:

- `bench_probe [seconds] | --upload <file>` — read-only board monitor, or a
  safe (motor never turns) upload-only test.
- `fetch_probe <dir> [--delete]` — drives a real fetch from a terminal.
- `series_probe --sweep <file> | --items A,B,sweep:<path> [--gap N]` —
  replicates the page's exact `BoardLink`/`SeriesRunner`/`RecordingNamer`
  wiring in C++, for bugs that only show up once something is actually
  reacting to the signals. **Uses a scratch QSettings identity
  (`"PdM Motor Control Test"`)** — its first version didn't, and silently
  overwrote the live app's real settings; if you ever add a new probe,
  copy this pattern, not the mistake.

### Bugs found and fixed, in the order they were found

1. **Delegate property shadowing** (M2). `ScenarioCard`'s `model` property
   shadowed the Repeater's injected `model` — every card rendered with empty
   fields. Renamed to `source`.
2. **`pgrep -x` truncation** (ongoing gotcha, not a code bug). Linux caps
   process names at 15 chars; `motor_control_gui` never matches. Bit bench
   testing repeatedly before being recognized as a pattern.
3. **`StackLayout` sizes to its tallest child** (M4). The record wizard and
   later the replay dialog both rendered as a mostly-empty box sized for
   their longest step, with the actual controls (including Close) far below
   the visible content — read by the user as "no way to close this window."
   Fixed by tracking `Layout.preferredHeight` off the current child's
   `implicitHeight` instead of letting `StackLayout` default.
4. **`RUN_MIN` vs. the analysis floor** (M2). A card-guide-line calculation
   nearly used the firmware's `RUN_MIN` (100, legal but electrically
   meaningless below the analysis floor) instead of the documented analysis
   floor of 132. Caught before shipping by reading the firmware source
   directly rather than trusting the repo's own README's framing.
5. **Fetch counter stuck past its threshold** (M3.5, found live on the
   bench). `RigFetcher`'s completed-run counter only reset on a **fully
   successful delete**. Any partial failure — one straggling file the guest
   was still writing when the fetch's `ls`/`wc -c` raced it — aborted the
   whole batch (deleting nothing, even files that *had* verified) and left
   the counter stuck above threshold, so the very next completed run
   re-triggered a second, differently-ranged fetch immediately. Fixed with
   three changes: the counter now resets the moment an attempt genuinely
   starts (past the folder/session checks), not on eventual success; one bad
   file is skipped rather than aborting the batch, and whatever verified
   still gets deleted; a 3 s settle delay was added before *automatic*
   fetches (manual "Fetch now" stays immediate) to reduce how often the race
   happens at all.
6. **A near-identical bug in the replay path**, found while fixing #7 below
   (naming). `root.recordingReplay` was read for the fetch-counter check
   *after* being reset to `false` two lines above — so a manual replay's
   recording never once counted toward a fetch. Same shape as #5, different
   code path, fixed with the same capture-before-reset pattern.
7. **Queue-preview double-counting** (naming rework). A scenario can appear
   twice in one series queue (asked for explicitly: running the same profile
   twice in a campaign is normal). The preview for the second occurrence has
   to add in every not-yet-run occurrence of the same label still ahead of
   it in the queue — the first version of this scanned from position 0
   *always*, which is right before anything runs and wrong afterward: once
   an earlier occurrence genuinely completes, its claim is already inside
   `RecordingNamer`'s own counter, and scanning from 0 counted it a second
   time on top. Caught by a test that checked the *actual run* against the
   *preview*, not just the preview alone. Fixed by scanning from the queue's
   current position, not 0.
8. **Custom sessions never actually replayed — in the series or standalone**
   (2026-08-20, the big one). `bench_probe --upload` had already proven a
   sweep uploads and verifies cleanly in isolation. The real fault: in
   `BoardLink::onLine()`, `emit uploadFinished(ok, outcome)` ran **one line
   before** `setState(UartIdle)`. Signal emission is synchronous — every
   listener (the series' `Connections` block, the standalone
   `ReplayDialog`) responds to a successful upload by immediately calling
   `board.startReplay()`, which refuses unless state is already
   `UartIdle`. At the moment those listeners ran, state was still
   `Uploading`. `startReplay()` returned `false`, silently, **every single
   time**, for every custom session, in every context — which is why
   scripted scenarios (a different code path) worked and every custom
   session did not. Fixed by reordering the two lines. **Proven fixed, not
   just reasoned about**: `series_probe` reproduced the exact failure before
   the fix (`startReplay() returned 0` immediately after a clean upload) and
   the exact success after it (a real 12 s replay, motor visibly turning in
   the live telemetry up to 746 rpm and back, `REPLAY DONE`, series
   correctly finishing).

### Naming scheme

`<prefix>_<label>_<count>` — e.g. `electric_4Rp_A_2`. Always numbered from 1,
never left bare on first use. One shared singleton
(`RecordingNamer`, in `PdM.MotorControl`) rather than three independent
schemes, because before this rework a manual "Run and record" from the grid,
a manual replay, and a series item each named files a different,
uncoordinated way — exactly the setup for two of them to silently collide.
A count is spent by a run that **completes**, never one that starts, so an
aborted run's file gets overwritten by the retry rather than the retry
jumping to the next number and leaving the incomplete file looking real.

### Rig access

Key auth is **impossible** on either SSH hop to the rig — both are QNX with
the boot image mounted read-only over `/`, and sshd resolves
`AuthorizedKeysFile` into that image. The working answer is a manually opened,
multiplexed control-socket session (`ssh -M -S ...`), which the app
*consumes* and never creates — creating one needs a password typed at a
terminal the app doesn't have. Full detail, the exact commands, and every
failure mode tried (and why each one failed) are in
[docs/RIG_ACCESS.md](../../pdm_motor_control_gui/docs/RIG_ACCESS.md) in that
repo.

## Where a fresh session should look, by task

- **"Something's broken in a tab"** → that tab's own repo, its README, and
  the bug list above for anything already known.
- **"Add a sixth tab"** → `docs/INTEGRATION_CONTRACT.md` in this repo, then
  copy `pdm_mlops_gui`'s shape (the cleanest example of an app written
  against the contract from scratch, no porting cruft).
- **"The rig won't talk to the app"** → `pdm_motor_control_gui/docs/
  RIG_ACCESS.md` for SSH, or `esp_dac/docs/02-board-states.md` for the
  serial protocol's state machine.
- **"Build the AI Agent tab"** → nothing exists yet. Read the design docs in
  `GP/ai/` (`pm_readme.md` and the two `HypridDesign`/`HypridAdabtiveDesign`
  files) before assuming it should be an LLM-with-tools agent — the existing
  design describes something narrower (a deterministic Q&A layer with
  optional LLM phrasing), which is both cheaper to build and more reliable
  to demo.
