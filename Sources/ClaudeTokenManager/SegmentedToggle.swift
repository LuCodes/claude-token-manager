import SwiftUI

/// Custom 2-option segmented toggle with proper contrast in dark mode.
struct SegmentedToggle<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .font(AppFont.inter(size: 11, weight: .medium))
                        .foregroundColor(
                            selection == option.value
                                ? Color(red: 241/255, green: 239/255, blue: 232/255)
                                : .white.opacity(0.5)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            selection == option.value
                                ? Color.white.opacity(0.12)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
