import SwiftUI
import UniformTypeIdentifiers

private struct DocumentDropTargetedKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var documentDropTargeted: Binding<Bool> {
        get { self[DocumentDropTargetedKey.self] }
        set { self[DocumentDropTargetedKey.self] = newValue }
    }
}

struct DocumentDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: (URL) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL] + DocumentTextExtractor.allowedContentTypes)
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false

        guard let provider = info.itemProviders(for: [.fileURL]).first else {
            return false
        }

        provider.loadDataRepresentation(for: .fileURL) { data, _ in
            guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }
            Task { @MainActor in
                onDrop(url)
            }
        }

        return true
    }
}
