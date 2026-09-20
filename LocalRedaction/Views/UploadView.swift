import SwiftUI

struct UploadView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var isTargeted = false

    var body: some View {
        ContentUnavailableView {
            Label("Abrir un documento", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("Arrastra un PDF o un archivo de texto a esta ventana.\nLos datos personales se analizan solo en este Mac.")
        } actions: {
            Button("Abrir…") {
                viewModel.presentOpenPanel()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.clear,
                    lineWidth: 2
                )
                .padding(12)
        }
        .onDrop(of: [.fileURL], delegate: DocumentDropDelegate(isTargeted: $isTargeted, onDrop: { url in
            viewModel.process(url: url)
        }))
        .accessibilityLabel("Arrastra un PDF o un archivo de texto para tachar datos personales")
    }
}

#if DEBUG
#Preview {
    UploadView()
        .environmentObject(AppViewModel())
        .frame(width: 980, height: 680)
}
#endif
