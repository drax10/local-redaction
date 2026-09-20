import SwiftUI

struct TypeBadge: View {
    let type: PIIType

    var body: some View {
        Text(type.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(.white)
            .background(type.badgeBackground, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityLabel(type.displayName)
    }
}
