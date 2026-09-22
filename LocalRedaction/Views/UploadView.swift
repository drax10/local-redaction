import SwiftUI

struct UploadView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ContentUnavailableView {
            Label("Abrir un documento", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("Arrastra un PDF, Word (.doc o .docx) o un archivo de texto a esta ventana.\nLos PDF escaneados se leen con OCR en este Mac.")
        } actions: {
            Button("Abrir…") {
                viewModel.presentOpenPanel()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Arrastra un PDF, Word o un archivo de texto para tachar datos personales")
    }
}

#if DEBUG
#Preview {
    UploadView()
        .environmentObject(AppViewModel())
        .frame(width: 980, height: 680)
}
#endif
