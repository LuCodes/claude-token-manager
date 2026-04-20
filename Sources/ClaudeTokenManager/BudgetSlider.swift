import SwiftUI

/// Minimal budget slider with a synchronized text input.
struct BudgetSlider: View {
    @Binding var value: Double
    let maxValue: Double
    let step: Double

    @State private var textValue: String = ""
    @FocusState private var isFocused: Bool

    init(value: Binding<Double>, maxValue: Double = 20.0, step: Double = 1.0) {
        self._value = value
        self.maxValue = maxValue
        self.step = step
    }

    private var ratio: CGFloat {
        max(0, min(CGFloat(value / maxValue), 1.0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Daily budget")
                    .font(AppFont.inter(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                HStack(spacing: 4) {
                    Text("$")
                        .font(AppFont.inter(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    TextField("", text: $textValue)
                        .textFieldStyle(.plain)
                        .font(AppFont.inter(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                        .focused($isFocused)
                        .onSubmit { commitText() }
                        .onChange(of: isFocused) { focused in
                            if !focused { commitText() }
                        }
                }
            }
            .padding(.bottom, 4)

            Text("Notify at 80% and 95% of budget")
                .font(AppFont.inter(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .padding(.bottom, 18)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 999)
                        .fill(Color(red: 55/255, green: 138/255, blue: 221/255))
                        .frame(width: ratio * geo.size.width, height: 4)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 2)
                        .offset(x: ratio * geo.size.width - 7)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let r = max(0, min(drag.location.x / geo.size.width, 1))
                            let raw = Double(r) * maxValue
                            let stepped = (raw / step).rounded() * step
                            value = stepped
                            syncTextFromValue()
                        }
                )
            }
            .frame(height: 14)

            HStack {
                Text("$0")
                    .font(AppFont.inter(size: 10))
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
                Text("$\(Int(maxValue))")
                    .font(AppFont.inter(size: 10))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.top, 8)

            Text("Tip: type any value above $\(Int(maxValue)) directly")
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.35))
                .padding(.top, 14)
                .padding(.bottom, 2)
        }
        .onAppear { syncTextFromValue() }
    }

    private func syncTextFromValue() {
        textValue = String(format: "%.2f", value)
    }

    private func commitText() {
        let cleaned = textValue
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = Double(cleaned), parsed >= 0 {
            value = parsed
        }
        syncTextFromValue()
    }
}
