import SwiftUI

@main
struct LocalRedactionApp: App {
    @StateObject private var viewModel = AppViewModel()

    init() {
        ScanNotificationService.shared.installDelegate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 920, minHeight: 520)
                .onOpenURL { url in
                    viewModel.process(url: url)
                }
        }
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Abrir…") {
                    viewModel.presentOpenPanel()
                }
                .keyboardShortcut("o")
                .disabled(!viewModel.canOpenDocument)

                Button("Nuevo documento") {
                    viewModel.showDropZone()
                }
                .keyboardShortcut("n")
                .disabled(!viewModel.canStartOver)
            }

            CommandGroup(after: .pasteboard) {
                Button("Copiar texto tachado") {
                    viewModel.copyToClipboard()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!viewModel.canCopyRedactedText)

                Button("Redactar") {
                    viewModel.redactSelectedText()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!viewModel.canRedactSelection)
            }
        }
    }
}
