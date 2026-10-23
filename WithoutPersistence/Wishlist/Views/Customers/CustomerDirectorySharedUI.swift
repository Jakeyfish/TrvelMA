import SwiftUI
import UIKit

struct CustomerAvatarPlaceholder: View {
    let name: String
    let size: CGFloat

    private var initial: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "?"
    }

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Circle().fill(Color.accentColor.opacity(0.12)))
            .clipShape(Circle())
    }
}

struct CustomerAvatarImage: View {
    let data: Data?
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                CustomerAvatarPlaceholder(name: name, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(Circle())
        .contentShape(Circle())
    }
}

enum CustomerListFilter: String, CaseIterable, Identifiable {
    case all, regular, agency

    var id: Self { self }
    var title: String {
        switch self {
        case .all: "全部"
        case .regular: "普通客户"
        case .agency: "旅行社"
        }
    }
    var icon: String {
        switch self {
        case .all: "person.2.fill"
        case .regular: "person.fill"
        case .agency: "building.2.fill"
        }
    }
}

struct CustomerDirectoryControls: View {
    @Environment(AppLanguageSettings.self) private var languageSettings
    let resultCount: Int
    @Binding var selectedFilter: CustomerListFilter
    @Binding var searchText: String
    let onAdd: () -> Void
    var isAddDisabled = false

    private var searchPlaceholder: String {
        switch languageSettings.selectedLanguage {
        case .simplifiedChinese: "搜索姓名、电话、邮箱、地址或备注"
        case .traditionalChinese: "搜尋姓名、電話、電子郵件、地址或備註"
        case .english: "Search name, phone, email, address, or notes"
        case .spanish: "Buscar nombre, teléfono, correo, dirección o notas"
        case .japanese: "名前、電話、メール、住所、メモを検索"
        case .korean: "이름, 전화, 이메일, 주소 또는 메모 검색"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("客户")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                        .background(Color(.secondarySystemGroupedBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isAddDisabled)
                .accessibilityLabel("新增客户")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)

            VStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(CustomerListFilter.allCases) { option in
                        Button { selectedFilter = option } label: {
                            Text(LocalizedStringKey(option.title))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background {
                                    if selectedFilter == option {
                                        Capsule().fill(Color(.systemBackground))
                                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color(.tertiarySystemGroupedBackground), in: Capsule())

                Rectangle().fill(Color.secondary.opacity(0.18)).frame(height: 1)

                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    SystemIMETextField(text: $searchText, placeholder: searchPlaceholder, capitalization: .none)
                        .id(languageSettings.identifier)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .fixedSize(horizontal: false, vertical: true)
                    if !searchText.isEmpty {
                        Button { withAnimation(.easeOut(duration: 0.15)) { searchText = "" } } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            HStack(spacing: 6) {
                Text("客户")
                Text("·")
                Text("\(resultCount)")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

}

struct CustomerDirectoryRow<Avatar: View>: View {
    let name: String
    let category: Int
    @ViewBuilder let avatar: () -> Avatar

    var body: some View {
        HStack(spacing: 14) {
            avatar()
            Text(name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
            Spacer(minLength: 4)
            Text(category == 2 ? "旅行社" : "普通客户")
                .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
