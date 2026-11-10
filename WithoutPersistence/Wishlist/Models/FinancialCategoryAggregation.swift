import Foundation

/// Chart grouping is by display name, while signed subtotals remain separate.
/// This does not apply the statement's absolute-value billing rule to finance.
enum FinancialCategoryAggregation {
    struct Entry {
        let title: String
        let amount: Double
        let isAddition: Bool
    }
    struct Group: Identifiable {
        let id: String
        let title: String
        var income: Double = 0
        var expense: Double = 0
        var amount: Double { income + expense }
        var isExpense: Bool { income == 0 && expense > 0 }
    }
    static func groups(_ entries: [Entry], fallback: String) -> [Group] {
        var values: [String: Group] = [:]
        for entry in entries where entry.amount.isFinite && abs(entry.amount) > 0.0001 {
            let cleaned = entry.title.precomposedStringWithCanonicalMapping.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            let title = cleaned.isEmpty ? fallback : cleaned
            var group = values[title] ?? Group(id: title, title: title)
            if entry.isAddition { group.income += abs(entry.amount) }
            else { group.expense += abs(entry.amount) }
            values[title] = group
        }
        return values.values.sorted {
            if $0.isExpense != $1.isExpense { return !$0.isExpense }
            if $0.amount != $1.amount { return $0.amount > $1.amount }
            return $0.id < $1.id
        }
    }
}
