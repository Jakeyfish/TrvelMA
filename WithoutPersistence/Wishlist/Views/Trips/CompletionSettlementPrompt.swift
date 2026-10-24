import SwiftUI

struct CompletionSettlementPrompt: ViewModifier {
    @Binding var isPresented: Bool
    let onSettle: () -> Void
    let onSkip: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack {
                        Color.black.opacity(0.42)
                            .ignoresSafeArea()

                        VStack(spacing: 18) {
                            Text("行程已结束")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text("是否财务结算？")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 12) {
                                promptButton("否", emphasized: false) {
                                    onSkip()
                                    isPresented = false
                                }

                                promptButton("是", emphasized: true) {
                                    onSettle()
                                    isPresented = false
                                }
                            }
                        }
                        .padding(22)
                        .frame(maxWidth: 340)
                        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
                        .padding(.horizontal, 24)
                        .accessibilityElement(children: .contain)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .zIndex(1000)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isPresented)
    }

    private func promptButton(_ title: LocalizedStringKey, emphasized: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(emphasized ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    emphasized ? Color.accentColor : Color(uiColor: .secondarySystemBackground),
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func completionSettlementPrompt(
        isPresented: Binding<Bool>,
        onSettle: @escaping () -> Void,
        onSkip: @escaping () -> Void = {}
    ) -> some View {
        modifier(CompletionSettlementPrompt(isPresented: isPresented, onSettle: onSettle, onSkip: onSkip))
    }
}
