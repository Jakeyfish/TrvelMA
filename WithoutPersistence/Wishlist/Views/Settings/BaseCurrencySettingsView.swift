import SwiftUI

struct BaseCurrencyOption: Identifiable, Hashable {
    let countryCode: String
    let countryName: String
    let currencyName: String
    let currencyEnglish: String
    let currencyCode: String
    let symbol: String
    let numberLocale: String
    let fractionDigits: Int

    var id: String { countryCode }
}

enum BaseCurrencyCatalog {
    static var countryCodeKey: String { "baseCurrency.countryCode.\(DataOwnership.activeScope)" }
    static let defaultCountryCode = "US"

    static let options: [BaseCurrencyOption] = [
        .init(countryCode: "US", countryName: "美国", currencyName: "美元", currencyEnglish: "US Dollar", currencyCode: "USD", symbol: "$", numberLocale: "en_US", fractionDigits: 2),
        .init(countryCode: "CA", countryName: "加拿大", currencyName: "加拿大元", currencyEnglish: "Canadian Dollar", currencyCode: "CAD", symbol: "CA$", numberLocale: "en_CA", fractionDigits: 2),
        .init(countryCode: "CN", countryName: "中国", currencyName: "人民币", currencyEnglish: "Chinese Yuan", currencyCode: "CNY", symbol: "¥", numberLocale: "zh_CN", fractionDigits: 2),
        .init(countryCode: "GB", countryName: "英国", currencyName: "英镑", currencyEnglish: "British Pound", currencyCode: "GBP", symbol: "£", numberLocale: "en_GB", fractionDigits: 2),
        .init(countryCode: "JP", countryName: "日本", currencyName: "日元", currencyEnglish: "Japanese Yen", currencyCode: "JPY", symbol: "¥", numberLocale: "ja_JP", fractionDigits: 0),
        .init(countryCode: "KR", countryName: "韩国", currencyName: "韩元", currencyEnglish: "South Korean Won", currencyCode: "KRW", symbol: "₩", numberLocale: "ko_KR", fractionDigits: 0),
        .init(countryCode: "ES", countryName: "西班牙", currencyName: "欧元", currencyEnglish: "Euro", currencyCode: "EUR", symbol: "€", numberLocale: "es_ES", fractionDigits: 2),
        .init(countryCode: "FR", countryName: "法国", currencyName: "欧元", currencyEnglish: "Euro", currencyCode: "EUR", symbol: "€", numberLocale: "fr_FR", fractionDigits: 2),
        .init(countryCode: "DE", countryName: "德国", currencyName: "欧元", currencyEnglish: "Euro", currencyCode: "EUR", symbol: "€", numberLocale: "de_DE", fractionDigits: 2),
        .init(countryCode: "AU", countryName: "澳大利亚", currencyName: "澳元", currencyEnglish: "Australian Dollar", currencyCode: "AUD", symbol: "A$", numberLocale: "en_AU", fractionDigits: 2),
        .init(countryCode: "HK", countryName: "中国香港", currencyName: "港元", currencyEnglish: "Hong Kong Dollar", currencyCode: "HKD", symbol: "HK$", numberLocale: "zh_HK", fractionDigits: 2),
        .init(countryCode: "TW", countryName: "中国台湾", currencyName: "新台币", currencyEnglish: "New Taiwan Dollar", currencyCode: "TWD", symbol: "NT$", numberLocale: "zh_TW", fractionDigits: 2),
        .init(countryCode: "SG", countryName: "新加坡", currencyName: "新加坡元", currencyEnglish: "Singapore Dollar", currencyCode: "SGD", symbol: "S$", numberLocale: "en_SG", fractionDigits: 2),
        .init(countryCode: "MX", countryName: "墨西哥", currencyName: "墨西哥比索", currencyEnglish: "Mexican Peso", currencyCode: "MXN", symbol: "MX$", numberLocale: "es_MX", fractionDigits: 2),
        .init(countryCode: "IN", countryName: "印度", currencyName: "印度卢比", currencyEnglish: "Indian Rupee", currencyCode: "INR", symbol: "₹", numberLocale: "en_IN", fractionDigits: 2),
        .init(countryCode: "CH", countryName: "瑞士", currencyName: "瑞士法郎", currencyEnglish: "Swiss Franc", currencyCode: "CHF", symbol: "CHF", numberLocale: "de_CH", fractionDigits: 2)
    ]

    static func option(for countryCode: String) -> BaseCurrencyOption {
        options.first { $0.countryCode == countryCode } ?? options[0]
    }

    static func format(_ amount: Double, countryCode: String) -> String {
        let option = option(for: countryCode)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: option.numberLocale)
        formatter.minimumFractionDigits = option.fractionDigits
        formatter.maximumFractionDigits = option.fractionDigits
        let number = formatter.string(from: NSNumber(value: abs(amount))) ?? String(abs(amount))
        let sign = amount < 0 ? "−" : ""
        return "\(sign)\(option.symbol)\(number)"
    }
}

struct BaseCurrencySettingsView: View {
    @Environment(\.locale) private var locale
    @AppStorage(BaseCurrencyCatalog.countryCodeKey)
    private var selectedCountryCode = BaseCurrencyCatalog.defaultCountryCode

    private var selectedCurrency: BaseCurrencyOption {
        BaseCurrencyCatalog.option(for: selectedCountryCode)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("国家和地区", selection: $selectedCountryCode) {
                        ForEach(BaseCurrencyCatalog.options) { option in
                            Text(Locale(identifier: locale.identifier).localizedString(forRegionCode: option.countryCode) ?? option.countryName)
                                .tag(option.countryCode)
                        }
                    }
                } header: {
                    Text("国家和地区")
                }

                Section {
                    LabeledContent("币种名称", value: "\(selectedCurrency.symbol) \(Locale(identifier: locale.identifier).localizedString(forCurrencyCode: selectedCurrency.currencyCode) ?? selectedCurrency.currencyEnglish)")
                    LabeledContent("币种英文", value: "\(selectedCurrency.currencyCode) · \(selectedCurrency.currencyEnglish)")
                } header: {
                    Text("本位币")
                } footer: {
                    Text("应用内所有金额将使用所选本位币显示，币种标识置于金额前。更改本位币不会自动换算已保存的金额。")
                }
            }
            .navigationTitle("本位币设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
