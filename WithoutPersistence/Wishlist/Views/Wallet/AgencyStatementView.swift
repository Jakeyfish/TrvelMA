import SwiftUI

struct AgencyStatementRow: Identifiable {
    struct Fee {
        let title: String
        let amount: Double
        let addition: Bool
        var key: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    let id: String
    let agencyCode: String
    let agencyName: String
    let date: Date
    let time: Date
    let order: String
    let service: String
    let guest: String
    let contact: String
    let route: String
    let memo: String
    let passengers: String
    let fare: Double
    let tip: Double
    let currency: String
    let fees: [Fee]
    var agencyKey: String { agencyCode.isEmpty ? "name:\(agencyName)" : "code:\(agencyCode)" }
    var total: Double { fare + fees.reduce(0) { $0 + abs($1.amount) } }
    func fee(_ key: String) -> Double { fees.filter { $0.key == key }.reduce(0) { $0 + abs($1.amount) } }
}

struct AgencyStatementSection: View {
    let rows: [AgencyStatementRow]
    @State private var agency = ""
    @State private var selected = Set<String>()
    @State private var statement: AgencyStatementSnapshot?
    private var agencies: [AgencyStatementRow] {
        Dictionary(grouping: rows, by: \.agencyKey).compactMap { $0.value.first }
            .sorted { $0.agencyKey < $1.agencyKey }
    }
    private var candidates: [AgencyStatementRow] {
        rows.filter { $0.agencyKey == agency }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.time != $1.time { return $0.time < $1.time }
            return $0.id < $1.id
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("对账单", systemImage: "doc.text").font(.headline)
            Text("按旅行社核对未结算行程").font(.caption).foregroundStyle(.secondary)
            Picker("旅行社", selection: $agency) {
                Text("请选择旅行社").tag("")
                ForEach(agencies) { item in
                    Text("\(item.agencyName) · \(item.agencyCode)").tag(item.agencyKey)
                }
            }
            .padding(10).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            if agency.isEmpty {
                Text("选择旅行社，勾选需要对账的未结算行程。已取消行程不参与对账。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(AppLocalization.format("%ld 条未结算行程", candidates.count)).font(.caption)
                    Spacer()
                    Button("全选") { selected = Set(candidates.map(\.id)) }
                    Button("清空") { selected.removeAll() }
                }
                ForEach(candidates) { row in
                    Button {
                        if selected.contains(row.id) { selected.remove(row.id) } else { selected.insert(row.id) }
                    } label: {
                        HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.guest.isEmpty ? AppLocalization.text("未填写客人") : row.guest).fontWeight(.semibold)
                            Text("\(row.date.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(AppLanguageSettings.currentLocale))) · \(row.time.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguageSettings.currentLocale)))").font(.caption).foregroundStyle(.secondary)
                            Text(AppLocalization.format("订单号 %@", row.order.isEmpty ? AppLocalization.text("未填写") : row.order)).font(.caption2).foregroundStyle(.secondary)
                        }.font(.subheadline)
                                            Spacer()
                        Image(systemName: selected.contains(row.id) ? "checkmark.square.fill" : "square")
                            .font(.title2).foregroundStyle(Color.accentColor)
                        }
                    }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(row.id) ? .isSelected : [])
                    .padding(14)
                    .background(selected.contains(row.id) ? Color.accentColor.opacity(0.06) : Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(selected.contains(row.id) ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), lineWidth: 1) }
                }
                Button(AppLocalization.format("对账单（%ld 条）", selected.count)) {
                    statement = AgencyStatementSnapshot(rows: candidates.filter { selected.contains($0.id) })
                }.buttonStyle(.borderedProminent).disabled(selected.isEmpty)
                Text("生成对账单仅供核对，不会改变行程结算状态。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .onChange(of: agency) { _, _ in selected.removeAll() }
        .onChange(of: rows.map(\.id)) { _, ids in selected.formIntersection(ids) }
        .sheet(item: $statement) { AgencyStatementSheet(snapshot: $0) }
    }
}

struct AgencyStatementSnapshot: Identifiable {
    let id = UUID()
    let rows: [AgencyStatementRow]
    var feeColumns: [String] { Set(rows.flatMap { $0.fees.map(\.key) }).sorted() }
    static func money(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(String(format: "%.2f", amount))"
    }
    var headers: [String] { ["日期", "订单号", "行程类型", "客人", "statement.route", "备注", "人数", "团费"].map(AppLocalization.text) + feeColumns + [AppLocalization.text("合计")] }
    func values(_ row: AgencyStatementRow) -> [String] {
        [row.date.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(AppLanguageSettings.currentLocale)), row.order,
         AppLocalization.text(row.service), row.guest, row.route + (row.contact.isEmpty ? "" : "\n" + AppLocalization.format("联系方式：%@", row.contact)), row.memo,
         row.passengers, Self.money(row.fare, currency: row.currency)]
        + feeColumns.map { Self.money(row.fee($0), currency: row.currency) } + [Self.money(row.total, currency: row.currency)]
    }
    var totals: [String] {
        Dictionary(grouping: rows, by: \.currency).sorted { $0.key < $1.key }.map { code, items in
            AppLocalization.format("合计：%@", Self.money(items.reduce(0) { $0 + $1.total }, currency: code))
        }
    }
    var csv: String {
        func line(_ values: [String]) -> String { values.map { value in
            let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: { value.hasPrefix($0) }) ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }
        return "\u{FEFF}" + ([line([AppLocalization.format("%@ 对账单", rows.first?.agencyName ?? "")]), line(headers)] + rows.map { line(values($0)) } + totals.map { line([$0]) }).joined(separator: "\r\n")
    }
}

private struct AgencyStatementSheet: View {
    let snapshot: AgencyStatementSnapshot
    @State private var pdfURL: URL?
    @State private var csvURL: URL?
    @State private var exportError: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalization.format("%@ 对账单", snapshot.rows.first?.agencyName ?? "")).font(.title2.bold())
                    Text(AppLocalization.format("%ld 条行程 · 未结算 · 仅供核对", snapshot.rows.count)).font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                            tableRow(snapshot.headers, header: true)
                            ForEach(Array(snapshot.rows.enumerated()), id: \.element.id) { index, row in
                                tableRow(snapshot.values(row), header: false, alternate: index.isMultiple(of: 2))
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    ForEach(snapshot.totals, id: \.self) { Text($0).font(.title3.bold()).padding(14)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12)) }
                    Text("仅供对账，未改变结算状态。").font(.caption).foregroundStyle(.secondary)
                }.padding()
            }
            .task {
                do { pdfURL = try snapshot.exportFile(pdf: true); csvURL = try snapshot.exportFile(pdf: false) }
                catch { exportError = AppLocalization.text("对账单文件生成失败，请关闭后重新打开。") }
            }
            .alert("无法分享", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("关闭", role: .cancel) { exportError = nil }
            } message: { Text(exportError ?? "") }
            .navigationTitle("对账单").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let pdfURL {
                        ShareLink(item: pdfURL) { Label("分享", systemImage: "square.and.arrow.up") }
                    } else {
                        ProgressView()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if let csvURL { ShareLink("导出 CSV", item: csvURL) }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
        }
    }
    private func tableRow(_ values: [String], header: Bool, alternate: Bool = false) -> some View {
        GridRow {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text(value.isEmpty ? "—" : value).font(.caption).fontWeight(header || index == values.count - 1 ? .semibold : .regular)
                    .monospacedDigit()
                    .foregroundStyle(header ? Color.secondary : index == values.count - 1 ? Color.accentColor : Color.primary)
                    .gridColumnAlignment(index >= 6 ? .trailing : .leading)
                    .fixedSize(horizontal: index != 4, vertical: true)
                    .frame(width: index == 4 ? 260 : nil, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: index >= 6 ? .topTrailing : .topLeading)
                    .background(header ? Color(.systemGray6) : index == values.count - 1 ? Color.accentColor.opacity(0.07) : alternate ? Color(.secondarySystemGroupedBackground) : Color(.systemBackground))
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.secondary.opacity(0.12)).frame(height: 0.5) }
            }
        }
    }
}
