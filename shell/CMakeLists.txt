#
# The shell is deliberately not a submodule. It is the one piece with no life
# outside Maestro: it owns main(), the window, and the bottom tab bar, and there
# is nothing to run standalone.
#
qt_add_executable(pdm_maestro
    main.cpp
)

# QT_QML_SINGLETON_TYPE is not inferred from the file, and getting it wrong is
# fatal rather than noisy. qt_add_qml_module generates the qmldir; unless the
# source is flagged here the generated entry will not say "singleton" while
# Theme.qml says `pragma Singleton`, and the mismatch takes down every file that
# imports it -- which is all of them -- leaving a process with no window.
set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(pdm_maestro
    URI PdM.Shell
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
        qml/PlaceholderPage.qml
)

# Widgets, not just Quick. Nothing in the shell draws a QWidget, but
# motor_recorder_gui builds against QApplication today, and the application
# object is a process-wide singleton chosen by whoever owns main() -- so Maestro
# has to construct the widest one any tab needs. Dropping to QGuiApplication is
# a later cleanup, and only once every app is known not to want it.
target_link_libraries(pdm_maestro PRIVATE
    Qt6::Quick
    Qt6::Qml
    Qt6::Widgets
    Qt6::QuickControls2
)

install(TARGETS pdm_maestro RUNTIME DESTINATION bin)
