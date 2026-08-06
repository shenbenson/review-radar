import SwiftUI

struct FilterChip: View {
    let title: String
    @Binding var isOn: Bool
    var isEnabled: Bool = true

    var body: some View {
        Button {
            guard isEnabled else { return }
            withAnimation(.easeInOut(duration: 0.12)) { isOn.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "checkmark" : "circle")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 10)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                isOn ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04),
                in: Capsule()
            )
            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            .overlay(
                Capsule()
                    .strokeBorder(isOn ? Color.accentColor.opacity(0.25) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}
