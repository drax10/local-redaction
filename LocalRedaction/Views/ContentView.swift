import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView(columnVisibility: $viewModel.columnVisibility) {
            DocumentSidebarView(isDropTargeted: $isDropTargeted)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 360)
        } detail: {
            NavigationStack {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .navigationTitle(viewModel.navigationTitle)
                    .toolbar { toolbarContent }
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: [.fileURL],
            delegate: DocumentDropDelegate(isTargeted: $isDropTargeted) { url in
                viewModel.process(url: url)
            }
        )
        .environment(\.documentDropTargeted, $isDropTargeted)
        .fileImporter(
            isPresented: $viewModel.isImporterPresented,
            allowedContentTypes: DocumentTextExtractor.allowedContentTypes,
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
        .confirmationDialog(
            "Este documento ya está analizado",
            isPresented: duplicatePromptBinding,
            titleVisibility: .visible
        ) {
            Button("Abrir el existente") {
                viewModel.openExistingInsteadOfRescan()
            }
            Button("Volver a analizar") {
                viewModel.rescanExistingDocument()
            }
            Button("Cancelar", role: .cancel) {
                viewModel.dismissDuplicatePrompt()
            }
        } message: {
            Text(duplicatePromptMessage)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch viewModel.state {
        case .upload:
            UploadView()
        case .processing:
            ProcessingView()
        case .reviewing, .completed:
            ReviewView()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
                    viewModel.cancelProcessing()
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
                    viewModel.showDropZone()
                } label: {
                    Label("Nuevo documento", systemImage: "plus")
                }
                .help("Abrir otro archivo")
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

    private var duplicatePromptBinding: Binding<Bool> {
        Binding(
            get: { viewModel.duplicatePrompt != nil },
            set: { if !$0 { viewModel.dismissDuplicatePrompt() } }
        )
    }

    private var duplicatePromptMessage: String {
        guard let name = viewModel.duplicatePrompt?.existing.fileName else {
            return "Este archivo ya está en el historial."
        }
        return "«\(name)» ya está en el historial con su texto y tachaduras. ¿Quieres abrirlo o analizarlo de nuevo?"
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
