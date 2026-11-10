import UIKit

extension AgencyStatementSnapshot {
    /// Actual files allow document share extensions (including WeChat) to accept the report.
    @MainActor func exportFile(pdf: Bool) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("statement-\(id.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(AppLocalization.text("对账单") + (pdf ? ".pdf" : ".csv"))
        if pdf { try pdfData().write(to: url, options: .atomic) }
        else { try Data(csv.utf8).write(to: url, options: .atomic) }
        return url
    }

    @MainActor func pdfData() -> Data {
        let font = UIFont.systemFont(ofSize: 10)
        let bold = UIFont.boldSystemFont(ofSize: 10)
        let title = AppLocalization.format("%@ 对账单", rows.first?.agencyName ?? "")
        let dataRows = rows.map { values($0) }
        let widths: [CGFloat] = headers.indices.map { i in
            if i == 4 { return 240 }
            let longest = ([headers[i]] + dataRows.map { $0[i] }).flatMap { $0.components(separatedBy: .newlines) }
                .map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 40
            return max(44, min(160, longest + 18))
        }
        let pageWidth = max(842, widths.reduce(0,+) + 48)
        let pageHeight: CGFloat = 595
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        let ink = UIColor(white: 0.18, alpha: 1)
        let tint = UIColor(red: 0.96, green: 0.94, blue: 0.90, alpha: 1)
        func attributes(_ index: Int, header: Bool) -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = index >= 6 ? .right : .left
            paragraph.lineBreakMode = .byWordWrapping
            return [.font: header ? bold : font, .foregroundColor: ink, .paragraphStyle: paragraph]
        }
        func height(_ values: [String], header: Bool) -> CGFloat {
            zip(values.indices, values).map { i, text in
                (text as NSString).boundingRect(with: CGSize(width: widths[i] - 16, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(i, header: header), context: nil).height + 20
            }.max().map { max(36, ceil($0)) } ?? 36
        }
        return renderer.pdfData { context in
            var y: CGFloat = 0
            var bottom: CGFloat = pageHeight - 40
            var page = 0
            @MainActor func drawRow(_ values: [String], header: Bool, alternate: Bool) {
                let h = height(values, header: header)
                var x: CGFloat = 24
                for (i, text) in values.enumerated() {
                    let rect = CGRect(x: x, y: y, width: widths[i], height: h)
                    (header || i == values.count - 1 ? tint : alternate ? UIColor(white: 0.98, alpha: 1) : .white).setFill()
                    context.cgContext.fill(rect)
                    (text as NSString).draw(with: rect.insetBy(dx: 8, dy: 10), options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: attributes(i, header: header), context: nil)
                    UIColor(white: 0.88, alpha: 1).setStroke()
                    context.cgContext.setLineWidth(0.5)
                    context.cgContext.move(to: CGPoint(x: x, y: y+h))
                    context.cgContext.addLine(to: CGPoint(x: x+widths[i], y: y+h))
                    context.cgContext.strokePath()
                    x += widths[i]
                }
                y += h
            }
            @MainActor func beginPage(minimumRowHeight: CGFloat = 0) {
                page += 1
                let h = max(pageHeight, minimumRowHeight + height(headers, header: true) + 130)
                context.beginPage(withBounds: CGRect(x: 0, y: 0, width: pageWidth, height: h), pageInfo: [:])
                bottom = h - 40
                (title as NSString).draw(at: CGPoint(x: 24,y: 20), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 18), .foregroundColor: ink])
                (AppLocalization.format("%ld 条行程 · 仅供对账 · 第 %ld 页", rows.count, page) as NSString).draw(at: CGPoint(x: 24,y: 48), withAttributes: [.font: font, .foregroundColor: UIColor.gray])
                y = 72
                drawRow(headers, header: true, alternate: false)
            }
            beginPage()
            for (i, row) in dataRows.enumerated() {
                let h = height(row, header: false)
                if y+h > bottom { beginPage(minimumRowHeight: h) }
                drawRow(row, header: false, alternate: i.isMultiple(of: 2))
            }
            let summary = totals.joined(separator: "\n") + "\n" + AppLocalization.text("仅供对账，未改变结算状态。")
            let summaryHeight = (summary as NSString).boundingRect(with: CGSize(width: pageWidth - 48, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: [.font: bold], context: nil).height + 24
            if y+summaryHeight > bottom { beginPage() }
            (summary as NSString).draw(in: CGRect(x: 24,y: y+12,width: pageWidth-48,height: summaryHeight), withAttributes: [.font: bold, .foregroundColor: ink])
        }
    }
}
