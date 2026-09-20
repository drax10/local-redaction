import SwiftUI

struct CandidateRow: View {
    @Binding var candidate: RedactionCandidate
    let tag: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("Incluir en el tachado", isOn: $candidate.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("Incluir este hallazgo en el documento tachado")

            TypePicker(type: $candidate.type)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.originalText)
                    .font(.body)
                    .textSelection(.enabled)
                    .lineLimit(2)

                Text(tag)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
