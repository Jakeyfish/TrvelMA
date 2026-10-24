import SwiftUI

struct TripCompletionConfirmationPrompt: ViewModifier {
    @Binding var isPresented: Bool
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack {
                        Color.black.opacity(0.42)
                            .ignoresSafeArea()
                            .onTapGesture { isPresented = false }

                        VStack(spacing: 18) {
                            Text("确认完成行程？")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text("确认后，该行程将标记为已完成。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 12) {
                                promptButton("取消", emphasized: false) {
                                    isPresented = false
                                }

                                promptButton("确认", emphasized: true) {
                                    onConfirm()
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
                    .zIndex(1001)
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
    func tripCompletionConfirmationPrompt(
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(TripCompletionConfirmationPrompt(isPresented: isPresented, onConfirm: onConfirm))
    }
}
