import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .upload:
                    UploadView()
                case .processing:
                    ProcessingView()
                case .reviewing, .completed:
                    ReviewView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle(viewModel.navigationTitle)
            .toolbar { toolbarContent }
            .fileImporter(
                isPresented: $viewModel.isImporterPresented,
                allowedContentTypes: [.pdf, .plainText, .utf8PlainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        viewModel.process(url: url)
                    }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
            .alert("No se pudo abrir el documento", isPresented: errorBinding) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !viewModel.sourceFileName.isEmpty, viewModel.state != .upload {
            ToolbarItem(placement: .navigation) {
                Label(viewModel.sourceFileName, systemImage: "doc")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
                    .help(viewModel.sourceFileName)
            }
        }

        switch viewModel.state {
        case .upload:
            ToolbarItem(placement: .primaryAction) {
                Button("Abrir…", systemImage: "folder") {
                    viewModel.presentOpenPanel()
                }
            }

        case .processing:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") {
                    viewModel.startOver()
                }
                .help("Cancelar el análisis")
            }

            ToolbarItem(placement: .status) {
                ProgressView(value: viewModel.processingProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
            }

        case .reviewing, .completed:
            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.startOver()
                } label: {
                    Label("Empezar de nuevo", systemImage: "arrow.counterclockwise")
                }
                .help("Empezar de nuevo")
                .labelStyle(.iconOnly)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.copyToClipboard()
                } label: {
                    Label(
                        viewModel.didCopy ? "Copiado" : "Copiar",
                        systemImage: viewModel.didCopy ? "checkmark" : "doc.on.clipboard"
                    )
                }
                .help(viewModel.didCopy ? "Copiado" : "Copiar el texto tachado")
                .labelStyle(.iconOnly)
                .disabled(viewModel.originalText.isEmpty)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}

#if DEBUG
#Preview("Inicio") {
    ContentView()
        .environmentObject(AppViewModel())
        .frame(width: 980, height: 680)
}

#Preview("Revisión") {
    ContentView()
        .environmentObject(AppViewModel.preview(state: .reviewing))
        .frame(width: 980, height: 680)
}
#endif
