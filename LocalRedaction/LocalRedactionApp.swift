import SwiftUI

@main
struct LocalRedactionApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 780, minHeight: 520)
        }
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Abrir…") {
                    viewModel.presentOpenPanel()
                }
                .keyboardShortcut("o")
                .disabled(!viewModel.canOpenDocument)

                Button("Empezar de nuevo") {
                    viewModel.startOver()
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
