import SwiftData
import SwiftUI

@main struct YtToPdfApp: App {
    private let history = HistoryContainer.make()
    @State private var settings = AppSettings()
    @State private var models = ModelManager()

    init() {
        FontRegistrar.registerBundledFonts()
        TemporaryWorkspace.removeStaleDirectories()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 820, minHeight: 560)
                .environment(\.historyIsPersistent, history.isPersistent)
                .environment(settings)
        }
        .defaultSize(width: 1120, height: 780)
        .modelContainer(history.container)
        .commands {
            ExportCommands(settings: settings)
        }

        Settings {
            SettingsView()
                .environment(settings)
                .environment(models)
        }
    }
}

extension EnvironmentValues {
    @Entry var historyIsPersistent = true
}
