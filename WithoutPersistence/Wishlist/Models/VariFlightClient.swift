import Foundation
import Security
import SwiftUI

struct VariFlightLookupResult: Codable, Hashable, Identifiable {
    let airlineName: String?
    let departureAirport: String?
    let arrivalAirport: String?
    let departureTerminal: String?
    let arrivalTerminal: String?
    let departureTime: String?
    let estimatedArrivalTime: String?
    let baggageCarousel: String?

    var id: String {
        [airlineName, departureAirport, arrivalAirport, departureTime, estimatedArrivalTime]
            .map { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "" }
            .joined(separator: "|")
    }

    var routeLabel: String {
        [departureAirport, arrivalAirport].compactMap { $0 }.joined(separator: " → ")
    }
}

struct SavedFlightSelection: Codable, Hashable {
    let flightNumber: String
    let flightDate: String
    let selected: VariFlightLookupResult
    let fetchedAt: Date

    init(flightNumber: String, flightDate: Date, selected: VariFlightLookupResult, fetchedAt: Date = .now) {
        self.flightNumber = flightNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        self.flightDate = formatter.string(from: flightDate)
        self.selected = selected
        self.fetchedAt = fetchedAt
    }

    func matches(flightNumber: String, flightDate: Date) -> Bool {
        let current = SavedFlightSelection(flightNumber: flightNumber, flightDate: flightDate, selected: selected, fetchedAt: fetchedAt)
        return self.flightNumber == current.flightNumber && self.flightDate == current.flightDate
    }
}

struct FlightCandidatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let candidates: [VariFlightLookupResult]
    let onSelect: (VariFlightLookupResult) -> Void

    var body: some View {
        NavigationStack {
            List(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                Button {
                    onSelect(candidate)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(candidate.routeLabel.isEmpty ? "航段 \(index + 1)" : candidate.routeLabel)
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        if let airline = candidate.airlineName, !airline.isEmpty {
                            Text(airline).font(.subheadline).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            if let time = candidate.departureTime, !time.isEmpty {
                                Label(time, systemImage: "airplane.departure")
                            }
                            if let time = candidate.estimatedArrivalTime, !time.isEmpty {
                                Label(time, systemImage: "airplane.arrival")
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("选择航段")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

enum VariFlightClientError: LocalizedError {
    case missingAPIKey
    case missingCloudSession
    case invalidFlightNumber
    case flightNotFound
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            String(localized: "请先在设置中保存飞友 API 密钥。", locale: AppLanguageSettings.currentLocale)
        case .missingCloudSession:
            String(localized: "云端登录状态已失效，请重新登录后查询航班。", locale: AppLanguageSettings.currentLocale)
        case .invalidFlightNumber:
            String(localized: "请输入有效的航班号。", locale: AppLanguageSettings.currentLocale)
        case .flightNotFound:
            String(localized: "没有找到该日期的航班，请检查航班号和日期。", locale: AppLanguageSettings.currentLocale)
        case .requestFailed(let message):
            message
        case .invalidResponse:
            String(localized: "航班接口返回的数据无法识别。", locale: AppLanguageSettings.currentLocale)
        }
    }
}

enum VariFlightAPIKeyStore {
    private static let service = "com.yunshengtech.travelmanager.variflight"
    private static let account = "api-key"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let result = SecItemAdd(insert as CFDictionary, nil)
            guard result == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct VariFlightClient {
    private let variFlightEndpoint = URL(string: "https://ai.variflight.com/servers/aviation/mcp")!

    func lookup(flightNumber: String, flightDate: Date, cloudAccessToken: String? = nil) async throws -> VariFlightLookupResult {
        guard let result = try await lookupCandidates(flightNumber: flightNumber, flightDate: flightDate, cloudAccessToken: cloudAccessToken).first else {
            throw VariFlightClientError.flightNotFound
        }
        return result
    }

    func lookupCandidates(
        flightNumber: String,
        flightDate: Date,
        cloudAccessToken: String? = nil,
        departureAirport: String? = nil,
        arrivalAirport: String? = nil
    ) async throws -> [VariFlightLookupResult] {
        let apiKey = cloudAccessToken == nil ? VariFlightAPIKeyStore.read() : nil
        if cloudAccessToken == nil && (apiKey?.isEmpty != false) { throw VariFlightClientError.missingAPIKey }
        if cloudAccessToken?.isEmpty == true { throw VariFlightClientError.missingCloudSession }

        let flightNumber = flightNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        guard !flightNumber.isEmpty else { throw VariFlightClientError.invalidFlightNumber }

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // VariFlight's remote MCP endpoint is stateless Streamable HTTP; call the tool directly.
        var arguments: [String: String] = ["fnum": flightNumber, "date": dateFormatter.string(from: flightDate)]
        if let departureAirport = Self.normalizedAirportCode(departureAirport) { arguments["dep"] = departureAirport }
        if let arrivalAirport = Self.normalizedAirportCode(arrivalAirport) { arguments["arr"] = arrivalAirport }

        let response = try await sendRPC(
            id: 1,
            method: "tools/call",
            params: [
                "name": "searchFlightsByNumber",
                "arguments": arguments
            ],
            apiKey: apiKey,
            cloudAccessToken: cloudAccessToken,
            sessionID: nil
        )

        return try parseLookupResults(from: response.body)
    }

    private func sendRPC(
        id: Int,
        method: String,
        params: [String: Any],
        apiKey: String?,
        cloudAccessToken: String?,
        sessionID: String?
    ) async throws -> (body: Any, sessionID: String?) {
        let endpoint = cloudAccessToken == nil
            ? variFlightEndpoint
            : SupabaseAuthClient.endpoint(path: "/functions/v1/variflight-lookup")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        if let cloudAccessToken {
            request.setValue(SupabaseAuthClient.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(cloudAccessToken)", forHTTPHeaderField: "Authorization")
        } else if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if method != "initialize" {
            request.setValue("2025-03-26", forHTTPHeaderField: "MCP-Protocol-Version")
        }
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        if cloudAccessToken != nil {
            let arguments = params["arguments"] as? [String: String] ?? [:]
            var body: [String: String] = [
                "flightNumber": arguments["fnum"] ?? "",
                "flightDate": arguments["date"] ?? ""
            ]
            if let departureAirport = arguments["dep"] { body["departureAirport"] = departureAirport }
            if let arrivalAirport = arguments["arr"] { body["arrivalAirport"] = arrivalAirport }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else {
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0", "id": id, "method": method, "params": params
            ])
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw VariFlightClientError.invalidResponse }
        let responseSessionID = http.value(forHTTPHeaderField: "Mcp-Session-Id") ?? sessionID
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let message: String
            if cloudAccessToken != nil,
               let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let serverMessage = payload["error"] as? String {
                message = serverMessage
            } else {
                switch http.statusCode {
                case 401: message = String(localized: "飞友 API 密钥无效，请检查设置。", locale: AppLanguageSettings.currentLocale)
                case 403: message = String(localized: "飞友 API 余额不足或账户不可用，请检查控制台。", locale: AppLanguageSettings.currentLocale)
                case 429: message = String(localized: "查询次数已达上限，请稍后再试。", locale: AppLanguageSettings.currentLocale)
                default:
                    let detailText = detail.map { ": \($0)" } ?? ""
                    let format = String(localized: "飞友航班查询失败（HTTP %1$d）%2$@。", locale: AppLanguageSettings.currentLocale)
                    message = String(format: format, locale: AppLanguageSettings.currentLocale, arguments: [http.statusCode, detailText])
                }
            }
            throw VariFlightClientError.requestFailed(message)
        }
        return (try decodeMCPBody(data), responseSessionID)
    }

    /// Looks up all legs first, then supplements with an airport-filtered query when
    /// the trip direction and an explicit airport/terminal in its route imply one.
    /// The caller still presents every unique result for the user to choose.
    func lookupCandidatesForTrip(
        flightNumber: String,
        flightDate: Date,
        serviceType: String,
        locationStart: String,
        locationEnd: String,
        cloudAccessToken: String? = nil
    ) async throws -> [VariFlightLookupResult] {
        let airportHint: (code: String, isArrival: Bool)?
        if serviceType == "接机", let code = Self.explicitAirportCode(in: locationStart) {
            airportHint = (code, true)
        } else if serviceType == "送机", let code = Self.explicitAirportCode(in: locationEnd) {
            airportHint = (code, false)
        } else {
            airportHint = nil
        }

        let initial = try await lookupCandidates(
            flightNumber: flightNumber,
            flightDate: flightDate,
            cloudAccessToken: cloudAccessToken
        )
        guard let airportHint,
              !initial.contains(where: { Self.airportCode(in: airportHint.isArrival ? $0.arrivalAirport : $0.departureAirport) == airportHint.code }) else {
            return initial
        }

        // Keep the broad results if a provider does not support or return the filtered search.
        let supplemental = (try? await lookupCandidates(
            flightNumber: flightNumber,
            flightDate: flightDate,
            cloudAccessToken: cloudAccessToken,
            departureAirport: airportHint.isArrival ? nil : airportHint.code,
            arrivalAirport: airportHint.isArrival ? airportHint.code : nil
        )) ?? []
        var seen = Set<String>()
        return (initial + supplemental).filter { seen.insert($0.id).inserted }
    }

    private static func normalizedAirportCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return code.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) == nil ? nil : code
    }

    private static func explicitAirportCode(in location: String) -> String? {
        let normalized = location.uppercased()
        // Require airport context so ordinary three-letter words in addresses are not treated as IATA codes.
        guard normalized.range(of: #"\b[A-Z]{3}\b.{0,24}\b(?:AIRPORT|TERMINAL|机场)\b|\b(?:AIRPORT|机场).{0,24}\b[A-Z]{3}\b"#, options: .regularExpression) != nil,
              let match = normalized.range(of: #"\b[A-Z]{3}\b"#, options: .regularExpression) else { return nil }
        return String(normalized[match])
    }

    private static func airportCode(in value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.uppercased()
        guard let match = normalized.range(of: #"\b[A-Z]{3}\b"#, options: .regularExpression) else { return nil }
        return String(normalized[match])
    }

    private func decodeMCPBody(_ data: Data) throws -> Any {
        if let json = try? JSONSerialization.jsonObject(with: data) { return json }
        guard let text = String(data: data, encoding: .utf8) else { throw VariFlightClientError.invalidResponse }

        // Streamable HTTP may respond with one or more SSE message events.
        var events: [Any] = []
        var dataLines: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                appendSSEEvent(dataLines, to: &events)
                dataLines.removeAll()
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }
        appendSSEEvent(dataLines, to: &events)
        if events.count == 1 { return events[0] }
        if !events.isEmpty { return events }

        // Some gateways return JSON on individual lines without an SSE content type.
        for line in text.components(separatedBy: .newlines) {
            guard let lineData = line.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) else { continue }
            events.append(json)
        }
        if events.count == 1 { return events[0] }
        if !events.isEmpty { return events }
        let format = String(localized: "飞友接口返回的内容不是可识别的 JSON/SSE：%@", locale: AppLanguageSettings.currentLocale)
        throw VariFlightClientError.requestFailed(String(format: format, locale: AppLanguageSettings.currentLocale, arguments: [String(text.prefix(400))]))
    }

    private func appendSSEEvent(_ dataLines: [String], to events: inout [Any]) {
        guard !dataLines.isEmpty,
              let data = dataLines.joined(separator: "\n").data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return }
        events.append(json)
    }

    private func parseLookupResults(from response: Any) throws -> [VariFlightLookupResult] {
        if let batch = response as? [Any] {
            let parsed = batch.flatMap { (try? parseLookupResults(from: $0)) ?? [] }
            guard !parsed.isEmpty else { throw VariFlightClientError.invalidResponse }
            return unique(parsed)
        }
        guard let envelope = response as? [String: Any] else { throw VariFlightClientError.invalidResponse }
        if let error = envelope["error"] as? [String: Any] {
            let message = error["message"] as? String ?? String(localized: "飞友航班查询失败。", locale: AppLanguageSettings.currentLocale)
            throw VariFlightClientError.requestFailed(message)
        }
        guard let result = envelope["result"] as? [String: Any] else {
            let excerpt = String(String(describing: envelope).prefix(400))
            let format = String(localized: "飞友接口响应缺少 MCP result 对象：%@", locale: AppLanguageSettings.currentLocale)
            throw VariFlightClientError.requestFailed(String(format: format, locale: AppLanguageSettings.currentLocale, arguments: [excerpt]))
        }
        if (result["isError"] as? Bool) == true {
            let message = (result["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.first
                ?? String(localized: "飞友航班查询失败。", locale: AppLanguageSettings.currentLocale)
            throw VariFlightClientError.requestFailed(message)
        }

        var candidates: [Any] = []
        if let structured = result["structuredContent"] { candidates.append(structured) }
        if let data = result["data"] { candidates.append(data) }
        if let output = result["output"] { candidates.append(output) }
        if let contents = result["content"] as? [[String: Any]] {
            candidates.append(contentsOf: contents.compactMap { $0["text"] as? String })
        }
        if candidates.isEmpty { candidates.append(result) }

        let parsed = unique(candidates.flatMap { extractFlights(from: $0) })
        if !parsed.isEmpty { return parsed }
        let excerpt: String
        if let contents = result["content"] as? [[String: Any]],
           let text = contents.compactMap({ $0["text"] as? String }).first {
            excerpt = String(text.prefix(500))
        } else {
            let format = String(localized: "result 字段：%@", locale: AppLanguageSettings.currentLocale)
            excerpt = String(format: format, locale: AppLanguageSettings.currentLocale, arguments: [result.keys.sorted().joined(separator: ", ")])
        }
        let format = String(localized: "飞友接口已返回结果，但应用暂未识别其字段格式。响应片段：%@", locale: AppLanguageSettings.currentLocale)
        throw VariFlightClientError.requestFailed(String(format: format, locale: AppLanguageSettings.currentLocale, arguments: [excerpt]))
    }

    private func extractFlights(from value: Any) -> [VariFlightLookupResult] {
        if let text = value as? String {
            if let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) {
                return extractFlights(from: json)
            }
            if let fields = fieldsFromText(text) { return [makeResult(fields)] }
            return []
        }
        if let array = value as? [Any] { return unique(array.flatMap(extractFlights(from:))) }
        guard let object = value as? [String: Any] else { return [] }

        // Flight tools can return a summary object together with a nested list
        // of individual legs. Prefer those explicit leg records over the
        // summary, otherwise the caller sees one result and skips the picker.
        let nestedFlights = unique(object.keys.sorted().flatMap { key -> [VariFlightLookupResult] in
            let child = object[key]!
            if child is [Any] || child is [String: Any] {
                return extractFlights(from: child)
            }
            if let text = child as? String,
               let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                return extractFlights(from: json)
            }
            return []
        })
        if !nestedFlights.isEmpty { return nestedFlights }

        if let fields = directFields(from: object), isFlightRecord(fields) {
            return [makeResult(fields)]
        }
        return []
    }

    private func isFlightRecord(_ fields: [FlightField: String]) -> Bool {
        fields[.departureAirport] != nil || fields[.arrivalAirport] != nil
            || fields[.departure] != nil || fields[.arrival] != nil
            || fields[.airline] != nil
    }

    private func makeResult(_ fields: [FlightField: String]) -> VariFlightLookupResult {
        VariFlightLookupResult(
            airlineName: fields[.airline], departureAirport: fields[.departureAirport], arrivalAirport: fields[.arrivalAirport],
            departureTerminal: fields[.departureTerminal], arrivalTerminal: fields[.arrivalTerminal],
            departureTime: fields[.departure], estimatedArrivalTime: fields[.arrival], baggageCarousel: fields[.baggage]
        )
    }

    private func unique(_ results: [VariFlightLookupResult]) -> [VariFlightLookupResult] {
        var seen = Set<String>()
        return results.filter { seen.insert($0.id).inserted }
    }

    private enum FlightField { case airline, departureAirport, arrivalAirport, departureTerminal, arrivalTerminal, departure, arrival, baggage }

    private func fields(from value: Any) -> [FlightField: String]? {
        if let string = value as? String {
            if let data = string.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data),
               let parsed = fields(from: json) { return parsed }
            return fieldsFromText(string)
        }
        guard let object = value as? [String: Any] else {
            if let values = value as? [Any] {
                for item in values {
                    if let parsed = fields(from: item) { return parsed }
                }
            }
            return nil
        }

        var result = directFields(from: object) ?? [:]
        for nested in object.values {
            guard let parsed = fields(from: nested) else { continue }
            for (field, value) in parsed where result[field] == nil { result[field] = value }
        }
        return result.isEmpty ? nil : result
    }

    private func directFields(from object: [String: Any]) -> [FlightField: String]? {
        var result: [FlightField: String] = [:]
        for (key, value) in object.sorted(by: { $0.key < $1.key }) {
            guard let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            switch normalizedKey(key) {
            case "airline", "airlinename", "carrier", "carriername", "airlinetitle", "flightcompany":
                if result[.airline] == nil { result[.airline] = string }
            case "departureairport", "departureairportname", "depairport", "depairportname", "departurestation", "depname", "dep", "flightdept":
                if result[.departureAirport] == nil { result[.departureAirport] = string }
            case "arrivalairport", "arrivalairportname", "arrairport", "arrairportname", "arrivalstation", "arrname", "arr", "flightarr":
                if result[.arrivalAirport] == nil { result[.arrivalAirport] = string }
            case "flightdeptimeplandate", "departuretime", "departuredatetime", "scheduleddeparture", "scheduleddeparturetime", "estimateddeparture", "estimateddeparturetime", "plantime", "plantimeofdeparture", "plantimedeparture", "depttime", "deptdatetime", "deptime", "std", "flightdeptimereadydate":
                if result[.departure] == nil { result[.departure] = string }
            case "flightarrtimeplandate", "estimatedarrivaltime", "estimatedarrivedtime", "arrivalestimatedtime", "arrivaldatetime", "arrivaltime", "scheduledarrival", "scheduledarrivaltime", "plantimearrival", "arrtime", "arrdatetime", "arrivetime", "sta", "eta", "flightarrtimereadydate":
                if result[.arrival] == nil { result[.arrival] = string }
            case "flightdeptterminal", "flightdeptterminalname", "departureterminal", "depterminal", "terminaldeparture", "deptterminal":
                if result[.departureTerminal] == nil { result[.departureTerminal] = string }
            case "flightarrterminal", "flightarrterminalname", "arrivalterminal", "arrterminal", "terminalarrival", "terminalarr", "arriveterminal", "terminal":
                if result[.arrivalTerminal] == nil { result[.arrivalTerminal] = string }
            case "baggagecarousel", "baggagecarouselnumber", "carousel", "carouselnumber", "baggageclaim", "baggageclaimbelt", "baggagebelt", "arrbaggagecarousel", "luggagecarousel":
                if result[.baggage] == nil { result[.baggage] = string }
            default: break
            }
        }
        return result.isEmpty ? nil : result
    }

    private func fieldsFromText(_ text: String) -> [FlightField: String]? {
        let patterns: [(FlightField, String)] = [
            (.airline, #"(?:FlightCompany|航空公司|航司|airline(?:\s*name)?|carrier)[\"']?\s*[:：]\s*[\"']?([^\"'\n,，;；}]+)"#),
            (.departureAirport, #"(?:FlightDept|departureAirport|departureAirportName|depAirport|depAirportName|departureStation|起飞机场|出发机场|出发地|departure\s*airport|origin|from)[\"']?\s*[:：]\s*[\"']?([^\"'\n,，;；}]+)"#),
            (.arrivalAirport, #"(?:FlightArr|arrivalAirport|arrivalAirportName|arrAirport|arrAirportName|arrivalStation|到达机场|目的机场|到达地|arrival\s*airport|destination|to)[\"']?\s*[:：]\s*[\"']?([^\"'\n,，;；}]+)"#),
            (.departure, #"(?:FlightDeptimePlanDate|FlightDeptimeReadyDate|起飞时间|计划起飞|预计起飞|departure(?:\s*time)?|scheduled\s*departure|estimated\s*departure|STD)[\"']?\s*[:：]\s*[\"']?([^\"'\n,，;；}]+)"#),
            (.arrival, #"(?:FlightArrtimePlanDate|FlightArrtimeReadyDate|预计到达时间|到达时间|计划到达|预计到达|arrival(?:\s*time)?|estimated\s*arrival|scheduled\s*arrival|ETA|STA)[\"']?\s*[:：]\s*[\"']?([^\"'\n,，;；}]+)"#),
            (.departureTerminal, #"(?:FlightDeptTerminal(?:Name)?|出发航站楼|出发航站|departure\s*terminal|dep\s*terminal)\s*[\"']?\s*[:：]\s*[\"']?([^\"'\n,，;；}]+)"#),
            (.arrivalTerminal, #"(?:FlightArrTerminal(?:Name)?|到达航站楼|到达航站|到达航站区|arrival\s*terminal|arr\s*terminal|terminal)\s*[\"']?\s*[:：]\s*[\"']?([^\"'\n,，;；}]+)"#),
            (.baggage, #"(?:行李转盘|行李提取转盘|baggage\s*carousel|baggage\s*claim|carousel)\s*[:：]\s*[\"']?([^\"'\n,，;；}]+)"#)
        ]
        var result: [FlightField: String] = [:]
        for (field, pattern) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "`*")))
            if !value.isEmpty && result[field] == nil { result[field] = value }
        }
        return result.isEmpty ? nil : result
    }

    private func normalizedKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
