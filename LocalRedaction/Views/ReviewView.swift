import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            VSplitView {
                previewPane
                findingsPane
            }
            statusBar
        }
    }

    private var previewPane: some View {
        VStack(spacing: 0) {
            paneHeader("Documento tachado")
            RedactedPreviewTextView(
                text: viewModel.redactedPreview,
                highlightNeedle: viewModel.focusedPreviewNeedle,
                highlightPulse: viewModel.highlightPulse,
                onSelectionChange: { snippet in
                    viewModel.selectedPreviewText = snippet
                },
                onRedact: { snippet in
                    viewModel.addRedaction(fromSelectedText: snippet)
                }
            )
        }
        .frame(minHeight: 140)
    }

    private var findingsPane: some View {
        VStack(spacing: 0) {
            paneHeader("Datos detectados")

            if viewModel.candidates.isEmpty {
                ContentUnavailableView(
                    "No se detectaron datos personales",
                    systemImage: "checkmark.shield",
                    description: Text("Puedes copiar el documento o abrir otro archivo.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table($viewModel.candidates, selection: $viewModel.focusedCandidateID) {
                    TableColumn("Incluir") { $candidate in
                        Toggle("Incluir en el tachado", isOn: $candidate.isSelected)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .help("Incluir este hallazgo en el documento tachado")
                    }
                    .width(min: 52, ideal: 64, max: 80)

                    TableColumn("Tipo") { $candidate in
                        TypePicker(type: $candidate.type)
                    }
                    .width(min: 128, ideal: 148, max: 180)

                    TableColumn("Texto") { $candidate in
                        Text(candidate.originalText)
                            .lineLimit(2)
                    }

                    TableColumn("Etiqueta") { $candidate in
                        Text(viewModel.tag(for: candidate))
                            .font(.body.monospaced())
                            .foregroundStyle(candidate.isSelected ? Color.primary : Color.secondary)
                    }
                    .width(min: 120, ideal: 150, max: 190)
                }
                .tableStyle(.inset)
                .onChange(of: viewModel.focusedCandidateID) { _, _ in
                    viewModel.pulsePreviewHighlight()
                }
            }
        }
        .frame(minHeight: 180)
    }

    private func paneHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.bar)
            .overlay(alignment: .bottom) {
                Divider()
            }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(statusText)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var statusText: String {
        let total = viewModel.candidates.count
        if total == 0 {
            return "Ningún hallazgo"
        }
        return "\(viewModel.selectedCount) de \(total) seleccionados"
    }
}

#if DEBUG
#Preview {
    ReviewView()
        .environmentObject(AppViewModel.preview(state: .reviewing))
        .frame(width: 980, height: 680)
}
#endif
