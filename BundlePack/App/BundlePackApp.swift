import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in
            AppModel.shared.openArchive(url)
            application.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct BundlePackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("BundlePack", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 680, idealWidth: 700, maxWidth: 720, minHeight: 590)
        }
        .defaultSize(width: 700, height: 650)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open BundlePack…") { model.chooseArchive() }
                    .keyboardShortcut("o")
            }
        }
    }
}
