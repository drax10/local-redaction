import SwiftUI

struct ResultView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Text(viewModel.redactedPreview)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .accessibilityLabel("Texto del documento tachado")
    }
}

#if DEBUG
#Preview {
    ResultView()
        .environmentObject(AppViewModel.preview(state: .completed))
        .frame(width: 980, height: 680)
}
#endif
