# The integration contract

What an app repository must do to become a tab in Maestro, while staying a
repository that builds and runs on its own.

Nothing here is Maestro-specific ceremony. Every rule exists because *something
breaks* when three apps share one process, and the breakage is named alongside
each rule.

---

## 1. Build a library; guard the executable

```cmake
qt_add_library(pdm_datacollection STATIC
    mqttclient.cpp
    traceview.cpp
)

# ... qt_add_qml_module on the same target, see §2 ...

# Compiled only when someone builds this repo directly. Maestro pulls the repo
# in with add_subdirectory(), where PROJECT_IS_TOP_LEVEL is false and this whole
# block disappears.
if(PROJECT_IS_TOP_LEVEL)
    qt_add_executable(motor_gui main.cpp)
    target_link_libraries(motor_gui PRIVATE pdm_datacollection)
endif()
```

**Why:** only one `main()` can own the event loop. This is the mechanism that
lets the standalone binary keep existing without a hand-set option that four
repos could each get wrong. Needs CMake 3.21+.

## 2. Ship a QML module, not a flat resource bundle

```cmake
qt_add_qml_module(pdm_datacollection
    URI PdM.DataCollection
    VERSION 1.0
    QML_FILES
        DataCollectionPage.qml
        AppCard.qml
        ...
)
```

**Why:** `qt6_add_resources` puts QML at `qrc:/main.qml`. Three apps doing that
in one binary overwrite each other — last one linked wins, silently, with no
error and no warning. A URI namespaces the files to
`:/qt/qml/PdM/DataCollection/…` and the collision cannot happen.

**Gotcha:** static QML modules need to be imported explicitly from the
executable that links them, or the types resolve at build time and are missing
at runtime:

```cpp
#include <QtQml/qqmlextensionplugin.h>
Q_IMPORT_QML_PLUGIN(PdM_DataCollectionPlugin)
```

## 3. The root component is an `Item`, never an `ApplicationWindow`

Split the existing `main.qml` in two:

```qml
// DataCollectionPage.qml  -- everything that was inside the window
Item { /* ... */ }

// main.qml -- standalone only, and now trivial
import PdM.DataCollection
ApplicationWindow {
    visible: true
    DataCollectionPage { anchors.fill: parent }
}
```

**Why:** a tab cannot contain a window. `shell/qml/PlaceholderPage.qml` is the
smallest working example of the required shape.

Watch for anything that reached out to the window: `ApplicationWindow.window`,
window-level `Shortcut`s, `close()`, `showFullScreen()`. Those need a different
home, usually a signal the shell handles.

## 4. The library makes no process-wide decisions

Inside the library, never:

- construct `QApplication` / `QGuiApplication`
- call `QQuickStyle::setStyle`
- call `QCoreApplication::exit` or `qApp->quit()`
- create a `QQmlApplicationEngine`

**Why:** all of these are once-per-process and belong to whoever owns `main()`.
`QQuickStyle` in particular fails *silently* if called after the first Controls
type is instantiated. Keep them in the repo's own `main.cpp`, which Maestro does
not compile.

## 5. Colour comes from `PdM.Core`, not a local `Theme.qml`

**Why:** three singletons registered as `Theme` is a name collision, and three
palettes that drift is a product that looks assembled from parts.
`shell/qml/Theme.qml` currently holds the shared palette (copied verbatim from
`motor_recorder_gui`); it moves to `pdm-core` in Phase 1 and the app-local copies
are deleted then.

## 6. Own no top-level `Window`

Dialogs must be `Popup`/`Dialog` parented into the page, not free-floating
`Window` objects. **Why:** Maestro is a single-window application; a stray
window outlives its tab and cannot be managed by the shell.

## 7. Declare shared external dependencies through `cmake/`

Paho MQTT, for example, is found today by a bare `find_library` inside
`motor_recorder_gui`. Two apps doing that two different ways produces two
different results on the same machine. Use the shared find module.

## 8. Never block the GUI thread

No synchronous network or file call on the main thread — connect, publish with
`waitForCompletion`, large reads. Put them on a worker thread.

**Why:** this is the rule with real teeth, and one app already breaks it.
`motor_recorder_gui` calls Paho's synchronous `MQTTClient_connect` directly on
the GUI thread. Standing alone, the cost is its own window freezing for up to
its five-second connect timeout. Inside Maestro, one event loop is shared, so
that same call freezes **all four tabs** — including an OTA transfer running in
another tab that has nothing to do with it. `ota_update_gui` already does this
correctly, with a `QThread` worker.

## 9. Namespace your C++ types

Every class the app defines goes in `PdM::<AppName>`.

**Why:** `motor_recorder_gui` and `ota_update_gui` both defined a class called
`MqttClient` in the global namespace. Linking the second one into Maestro failed
with `multiple definition of MqttClient::publishCommand`. It is a link error, so
nothing ships broken — but it only appears once a *second* app is integrated, so
the first port looks fine and the trap is set for whoever does the next one.

QML type names are unaffected: `QML_ELEMENT` on `PdM::Ota::MqttClient` still
registers as `MqttClient` in `PdM.Ota`, because the module URI already separates
them.

## 10. No context properties

Expose objects as QML singletons (`QML_SINGLETON`), never with
`rootContext()->setContextProperty()`.

**Why:** two reasons, and either alone is enough. The root context belongs to
the engine, which the whole process shares, so a second app registering the same
name silently overwrites the first with no diagnostic anywhere. And the property
would be set from the app's own `main.cpp`, which Maestro never compiles — so in
the merged build it is simply never set and QML fails on an undefined name.

`ota_update_gui` exposed its scripted-control object this way; it is
`Control` as a `QML_SINGLETON` of `PdM.Ota` now.

## 11. Keep a CI job that builds the repo standalone

**Why:** this is the guard rail that makes the whole arrangement safe. Nothing
above breaks standalone use *by design* — but only a build that actually
exercises it will notice when someone breaks it by accident. Without this,
"each app works on its own" quietly stops being true and nobody finds out until
a fresh clone fails.

---

## Declaring compliance

Add a `pdm-app.cmake` marker file at the repo root. Maestro's top-level
`CMakeLists.txt` compiles an app in only when that file is present, so a
submodule that is checked out but not yet ported keeps its placeholder tab
instead of breaking the build. The file eventually carries the app's metadata
(id, title, glyph, library target, QML module URI); for now its presence is the
signal.
