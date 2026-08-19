#
# PdM Maestro -- one window over the four tools of the predictive-maintenance
# toolchain. Each tool stays a repository of its own that builds and runs on its
# own; this build stitches them into a single process.
#
# 3.21 is the floor and the reason is load-bearing. PROJECT_IS_TOP_LEVEL arrived
# in 3.21, and it is what lets an app repo compile its own main() when someone
# builds it directly and skip it when Maestro pulls it in with
# add_subdirectory(). Without that variable each app would need a hand-set
# option, which is one more thing to get wrong in one of four places.
#
cmake_minimum_required(VERSION 3.21)

project(PdMMaestro
    VERSION 0.1.0
    DESCRIPTION "Unified shell for the PdM toolchain"
    LANGUAGES CXX
)

# 6.5 is the floor for the whole design, not a preference. The apps are merged
# as QML modules rather than as flat .qrc bundles, because three apps that each
# load "qrc:/main.qml" silently overwrite each other in one binary; the URI
# namespace is what makes them coexist. Module-based loading
# (engine.loadFromModule) and reliable static QML plugin handling both want 6.5
# or newer. The system Qt here is 6.2.4, so this will fail on the default
# CMAKE_PREFIX_PATH -- use the preset, which points at ~/Qt/6.10.3/gcc_64.
find_package(Qt6 6.5 REQUIRED COMPONENTS Quick Qml Widgets QuickControls2)

qt_standard_project_setup(REQUIRES 6.5)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Runtime output all lands in one place so the built shell can be launched by a
# stable path regardless of which subdirectory produced it.
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

#
# ---- core -------------------------------------------------------------------
#
# Added before the apps, and that order is load-bearing. Each app repo carries
# pdm_app_core as its own submodule so it can build standalone, and guards the
# add_subdirectory with if(NOT TARGET pdm_core). Adding core here first is what
# makes those guards fire, so every app in a Maestro build resolves against the
# one commit Maestro pins rather than four independently pinned copies of the
# same QML module URI.
#
if(NOT TARGET pdm_core)
    add_subdirectory(core)
endif()

#
# ---- apps -------------------------------------------------------------------
#
# The four tabs, in the order they appear along the bottom of the window. Each
# name is a directory under apps/ and, once the repo exists, a submodule.
#
set(PDM_APPS
    data_collection
    motor_control
    mlops
    ota
    agent
)

# An app is compiled into Maestro only once it carries a pdm-app.cmake marker in
# its root -- the file the port adds when the repo starts satisfying
# docs/INTEGRATION_CONTRACT.md. A submodule that is merely *present* is not
# enough: motor_recorder_gui and ota_update_gui are both checked out already and
# both still build a bare add_executable() with their QML in a flat resource
# bundle, so add_subdirectory() on them today would produce a second binary and
# a resource collision rather than a tab.
#
# The practical effect is that the migration state is visible in the configure
# output, and wiring an app up is a one-file change in the app's own repo rather
# than an edit here.
set(PDM_INTEGRATED_APPS "")
set(PDM_APP_TARGETS "")
set(PDM_APP_DEFINES "")
foreach(app IN LISTS PDM_APPS)
    set(app_dir "${CMAKE_CURRENT_SOURCE_DIR}/apps/${app}")
    if(EXISTS "${app_dir}/pdm-app.cmake")
        # Cleared first: a marker file that forgets to set one of these would
        # otherwise silently inherit the previous app's value and link the wrong
        # target, which is a confusing failure a long way from its cause.
        unset(PDM_APP_ID)
        unset(PDM_APP_TARGET)
        unset(PDM_APP_PLUGIN)
        unset(PDM_APP_QML_URI)
        unset(PDM_APP_DEFINE)
        include("${app_dir}/pdm-app.cmake")

        message(STATUS "PdM app '${app}': integrated as ${PDM_APP_TARGET} (${PDM_APP_QML_URI})")
        add_subdirectory("apps/${app}")

        # Both halves of the app's static QML module, same as core: the library
        # carries the types, the plugin carries the registration.
        list(APPEND PDM_APP_TARGETS ${PDM_APP_TARGET} ${PDM_APP_PLUGIN})
        list(APPEND PDM_APP_DEFINES ${PDM_APP_DEFINE})
        list(APPEND PDM_INTEGRATED_APPS "${app}")
    elseif(EXISTS "${app_dir}/CMakeLists.txt")
        message(STATUS "PdM app '${app}': checked out, not yet ported -- placeholder tab")
    else()
        message(STATUS "PdM app '${app}': absent -- placeholder tab")
    endif()
endforeach()

add_subdirectory(shell)
