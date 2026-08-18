#
# The shell is deliberately not a submodule. It is the one piece with no life
# outside Maestro: it owns main(), the window, and the bottom tab bar, and there
# is nothing to run standalone.
#
qt_add_executable(pdm_maestro
    main.cpp
)

qt_add_qml_module(pdm_maestro
    URI PdM.Shell
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/PlaceholderPage.qml
)

# Widgets, not just Quick. Nothing in the shell draws a QWidget, but
# motor_recorder_gui builds against QApplication today, and the application
# object is a process-wide singleton chosen by whoever owns main() -- so Maestro
# has to construct the widest one any tab needs. Dropping to QGuiApplication is
# a later cleanup, and only once every app is known not to want it.
# Both halves of the QML module, and both are needed. pdm_core carries the C++
# types and the compiled QML; pdm_coreplugin carries the registration that
# Q_IMPORT_QML_PLUGIN in main.cpp refers to. Linking only the library gets an
# "undefined reference to qt_static_plugin_PdM_CorePlugin()" at link time --
# which at least fails loudly, unlike omitting the Q_IMPORT_QML_PLUGIN, which
# builds clean and fails at run time.
target_link_libraries(pdm_maestro PRIVATE
    pdm_core
    pdm_coreplugin
    ${PDM_APP_TARGETS}
    Qt6::Quick
    Qt6::Qml
    Qt6::Widgets
    Qt6::QuickControls2
)

# One PDM_HAVE_<APP> per integrated app, from its pdm-app.cmake marker. main.cpp
# guards each app's registration call with these, so the shell compiles against
# whatever subset of the four is present -- which is every state the migration
# passes through.
target_compile_definitions(pdm_maestro PRIVATE ${PDM_APP_DEFINES})

install(TARGETS pdm_maestro RUNTIME DESTINATION bin)
