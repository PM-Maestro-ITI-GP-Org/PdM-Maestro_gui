#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QtQml/qqmlextensionplugin.h>

#include "appregistry.h"

/*
 * Static QML modules have to be imported explicitly by the executable that
 * links them. Without this the PdM.Core types resolve at build time -- the QML
 * compiles, the build is clean -- and are simply missing at run time, which
 * presents as "Theme is not a type" from a file that plainly imports PdM.Core.
 * One line per app module as each port lands.
 */
Q_IMPORT_QML_PLUGIN(PdM_CorePlugin)

#ifdef PDM_HAVE_DATA_COLLECTION
#include "datacollectionapp.h"
Q_IMPORT_QML_PLUGIN(PdM_DataCollectionPlugin)
#endif

#ifdef PDM_HAVE_OTA
#include "otaapp.h"
Q_IMPORT_QML_PLUGIN(PdM_OtaPlugin)
#endif

#ifdef PDM_HAVE_MLOPS
#include "mlopsapp.h"
Q_IMPORT_QML_PLUGIN(PdM_MlOpsPlugin)
#endif

#ifdef PDM_HAVE_MOTOR_CONTROL
#include "motorcontrolapp.h"
Q_IMPORT_QML_PLUGIN(PdM_MotorControlPlugin)
#endif

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

    /* Read by QSettings, which is how BrokerSettings persists the MQTT
       endpoint. Set before anything touches core. */
    app.setOrganizationName("PM-Maestro-ITI-GP-Org");
    app.setApplicationName("PdM Maestro");

    /* Must precede the engine. QQuickStyle is ignored once the first Controls
       type has been instantiated, and the failure is silent -- the app simply
       renders in the default style and nobody can see why. */
    QQuickStyle::setStyle("Material");

    /*
     * The four tabs, in the order they appear along the bottom.
     *
     * Declared here rather than in QML so that the list survives an app being
     * absent: an entry with no pageUrl renders as a placeholder that reports
     * where its port stands. Each app calls AppRegistry::setPage() from its own
     * library as it lands, and the tab becomes real without this list changing.
     */
    auto *registry = PdM::AppRegistry::instance();

    registry->registerApp({
        { "id",        "data_collection" },
        { "title",     QObject::tr("Data Collection") },
        { "glyph",     "◉" },
        { "moduleUri", "PdM.DataCollection" },
        { "repo",      "motor_recorder_gui" },
        { "status",    QObject::tr("Phase 2. Checked out under apps/data_collection and still "
                                   "builds as a standalone app; not yet split into a library "
                                   "and a page.") },
    });

    registry->registerApp({
        { "id",        "motor_control" },
        { "title",     QObject::tr("Motor Control") },
        { "glyph",     "\u2299" },
        { "moduleUri", "PdM.MotorControl" },
        { "repo",      "pdm_motor_control_gui" },
        { "status",    QObject::tr("Runs the scripted A-J drive profiles on the ESP32 rig "
                                   "and records custom hand sweeps.") },
    });

    registry->registerApp({
        { "id",        "mlops" },
        { "title",     QObject::tr("ML / Ops") },
        { "glyph",     "◆" },
        { "moduleUri", "PdM.MlOps" },
        { "repo",      "pdm_mlops_gui" },
        { "status",    QObject::tr("Phase 4. The training pipeline lives in the AI repo and has "
                                   "no GUI, so this tab is written against the contract from the "
                                   "start rather than ported to it.") },
    });

    registry->registerApp({
        { "id",        "ota" },
        { "title",     QObject::tr("OTA Update") },
        { "glyph",     "↓" },
        { "moduleUri", "PdM.Ota" },
        { "repo",      "ota_update_gui" },
        { "status",    QObject::tr("Phase 3. Checked out under apps/ota and still builds as a "
                                   "standalone app; not yet split into a library and a page.") },
    });

    registry->registerApp({
        { "id",        "agent" },
        { "title",     QObject::tr("AI Agent") },
        { "glyph",     "★" },
        { "moduleUri", "PdM.Agent" },
        { "repo",      "pdm_agent_gui (to be created)" },
        { "status",    QObject::tr("Phase 5, lowest priority. The tab exists now so the "
                                   "four-tab layout is real and the slot is reserved.") },
    });

    /*
     * Each integrated app hands the shell its page, turning that entry's
     * placeholder into the real tab. The app owns its own page URL, so moving
     * or renaming a page is a change inside that app's repository alone.
     *
     * After the registerApp() calls above, since setPage() needs the id to
     * already exist.
     */
#ifdef PDM_HAVE_DATA_COLLECTION
    PdM::DataCollection::registerWithShell();
#endif

#ifdef PDM_HAVE_OTA
    PdM::Ota::registerWithShell();
#endif

#ifdef PDM_HAVE_MLOPS
    PdM::MlOps::registerWithShell();
#endif

#ifdef PDM_HAVE_MOTOR_CONTROL
    PdM::MotorControl::registerWithShell();
#endif

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
