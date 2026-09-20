import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.regular)

            VStack(spacing: 6) {
                Text("Analizando en este Mac")
                    .font(.title2.weight(.semibold))

                Text(viewModel.processingStatus)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }

            ProgressView(value: viewModel.processingProgress)
                .progressViewStyle(.linear)
                .frame(width: 280)

            VStack(alignment: .leading, spacing: 8) {
                stepRow("Leyendo el documento", done: viewModel.processingProgress > 0.08)
                stepRow("Identificadores RFC, CURP, CLABE y cédula", done: viewModel.processingProgress >= 0.45)
                stepRow("Nombres, empresas, domicilios y otros datos", done: viewModel.processingProgress >= 0.88)
                stepRow("Preparando resultados", done: viewModel.processingProgress >= 1)
            }
            .padding(.top, 8)

            if !viewModel.sourceFileName.isEmpty {
                Text(viewModel.sourceFileName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: viewModel.processingStatus)
        .animation(.easeInOut(duration: 0.2), value: viewModel.processingProgress)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Procesando. \(viewModel.processingStatus)")
    }

    private func stepRow(_ title: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.accentColor : Color.secondary)
                .imageScale(.small)
            Text(title)
                .font(.callout)
                .foregroundStyle(done ? Color.primary : Color.secondary)
        }
    }
}

#if DEBUG
#Preview {
    ProcessingView()
        .environmentObject(AppViewModel.preview(state: .processing))
        .frame(width: 980, height: 680)
}
#endif
