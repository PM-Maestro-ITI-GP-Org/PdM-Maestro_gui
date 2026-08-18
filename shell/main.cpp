#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>

/*
 * The single entry point of the merged application.
 *
 * Everything here is a process-wide decision that cannot be made twice, which
 * is exactly why the integration contract forbids the app libraries from doing
 * any of it: one application object, one style, one engine. An app repo keeps
 * its own main.cpp for standalone use, but that file is not compiled when
 * Maestro pulls the repo in -- see PROJECT_IS_TOP_LEVEL in the top-level
 * CMakeLists.txt.
 */
int main(int argc, char *argv[])
{
    /* QApplication rather than QGuiApplication: see the note on the Widgets
       link in CMakeLists.txt. */
    QApplication app(argc, argv);

    app.setOrganizationName("PM-Maestro-ITI-GP-Org");
    app.setApplicationName("PdM Maestro");

    /* Must precede the engine. QQuickStyle is ignored once the first Controls
       type has been instantiated, and the failure is silent -- the app simply
       renders in the default style and nobody can see why. */
    QQuickStyle::setStyle("Material");

    QQmlApplicationEngine engine;

    /* A QML error is otherwise completely silent: load() returns, exec() runs,
       and the user gets a process with no window and no message.
       objectCreationFailed reports it directly (Qt 6.4+). */
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, []() {
                         qCritical("[maestro] FATAL: QML object creation failed");
                         QCoreApplication::exit(1);
                     }, Qt::QueuedConnection);

    /* By module URI, not by file path. Once the app submodules are linked in,
       each contributes its own URI (PdM.DataCollection and friends) and the
       flat "qrc:/main.qml" collision that would come from four resource
       bundles never arises. */
    engine.loadFromModule("PdM.Shell", "Main");

    return app.exec();
}
