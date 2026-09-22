import SwiftUI

struct DocumentSidebarView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Binding var isDropTargeted: Bool
    @State private var documentPendingDeletion: CachedDocumentSummary?

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            documentList
        }
        .navigationTitle("Documentos")
        .onDrop(
            of: [.fileURL],
            delegate: DocumentDropDelegate(isTargeted: $isDropTargeted) { url in
                viewModel.process(url: url)
            }
        )
        .confirmationDialog(
            "¿Eliminar este documento del historial?",
            isPresented: deletionDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                if let documentPendingDeletion {
                    viewModel.deleteCachedDocument(id: documentPendingDeletion.id)
                }
                documentPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) {
                documentPendingDeletion = nil
            }
        } message: {
            if let documentPendingDeletion {
                Text("Se quitará «\(documentPendingDeletion.fileName)» de este Mac. El archivo original no se borra.")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Buscar", text: $viewModel.sidebarSearch)
                .textFieldStyle(.plain)
                .controlSize(.small)
            if !viewModel.sidebarSearch.isEmpty {
                Button {
                    viewModel.sidebarSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Borrar búsqueda")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(10)
    }

    @ViewBuilder
    private var documentList: some View {
        if viewModel.sidebarDocuments.isEmpty {
            ContentUnavailableView(
                "Sin documentos",
                systemImage: "doc.text",
                description: Text("Los archivos que analices aparecerán aquí, con el texto y las tachaduras guardados en este Mac.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.filteredDocuments.isEmpty {
            ContentUnavailableView.search(text: viewModel.sidebarSearch)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: selectionBinding) {
                ForEach(viewModel.filteredDocuments) { document in
                    DocumentSidebarRow(
                        document: document,
                        isProcessing: viewModel.isProcessingDocument(document.id),
                        progress: viewModel.processingProgress,
                        status: viewModel.processingStatus
                    )
                    .tag(document.id)
                    .contextMenu {
                        if viewModel.isProcessingDocument(document.id) {
                            Button("Cancelar análisis") {
                                viewModel.cancelProcessing()
                            }
                        } else {
                            Button("Eliminar…", role: .destructive) {
                                documentPendingDeletion = document
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.selectedDocumentID },
            set: { viewModel.selectCachedDocument(id: $0) }
        )
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { documentPendingDeletion != nil },
            set: { if !$0 { documentPendingDeletion = nil } }
        )
    }
}

private struct DocumentSidebarRow: View {
    let document: CachedDocumentSummary
    let isProcessing: Bool
    var progress: Double = 0
    var status: String = ""

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(document.fileName)
                    .lineLimit(1)
                if isProcessing {
                    ProgressView(value: min(max(progress, 0.02), 1))
                        .progressViewStyle(.linear)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            if isProcessing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: document.systemImage)
            }
        }
        .padding(.vertical, 2)
        .accessibilityLabel(isProcessing ? "\(document.fileName). \(status)" : document.fileName)
    }

    private var subtitle: String {
        let findings = document.candidateCount == 1
            ? "1 hallazgo"
            : "\(document.candidateCount) hallazgos"
        return "\(findings) · \(document.updatedAt.formatted(.relative(presentation: .named)))"
    }
}

#if DEBUG
#Preview {
        NavigationSplitView {
            DocumentSidebarView(isDropTargeted: .constant(false))
                .navigationSplitViewColumnWidth(250)
    } detail: {
        Text("Detalle")
    }
    .environmentObject(AppViewModel.preview(state: .reviewing))
    .frame(width: 980, height: 680)
}
#endif
