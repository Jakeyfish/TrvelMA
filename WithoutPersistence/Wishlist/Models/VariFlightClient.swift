import Foundation
import Security

struct VariFlightLookupResult {
    let airlineName: String?
    let departureAirport: String?
    let arrivalAirport: String?
    let departureTerminal: String?
    let arrivalTerminal: String?
    let departureTime: String?
    let estimatedArrivalTime: String?
    let baggageCarousel: String?
}

enum VariFlightClientError: LocalizedError {
    case missingAPIKey
    case invalidFlightNumber
    case flightNotFound
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            String(localized: "请先在设置中保存飞友 API 密钥。")
        case .invalidFlightNumber:
            String(localized: "请输入有效的航班号。")
        case .flightNotFound:
            String(localized: "没有找到该日期的航班，请检查航班号和日期。")
        case .requestFailed(let message):
            message
        case .invalidResponse:
            String(localized: "航班接口返回的数据无法识别。")
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
    private let endpoint = URL(string: "https://ai.variflight.com/servers/aviation/mcp")!

    func lookup(flightNumber: String, flightDate: Date) async throws -> VariFlightLookupResult {
        guard let apiKey = VariFlightAPIKeyStore.read(), !apiKey.isEmpty else {
            throw VariFlightClientError.missingAPIKey
        }

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
        let response = try await sendRPC(
            id: 1,
            method: "tools/call",
            params: [
                "name": "searchFlightsByNumber",
                "arguments": ["fnum": flightNumber, "date": dateFormatter.string(from: flightDate)]
            ],
            apiKey: apiKey,
            sessionID: nil
        )

        let result = try parseLookupResult(from: response.body)
        guard result.airlineName != nil || result.departureAirport != nil || result.arrivalAirport != nil
                || result.departureTime != nil || result.estimatedArrivalTime != nil
                || result.departureTerminal != nil || result.arrivalTerminal != nil || result.baggageCarousel != nil else {
            throw VariFlightClientError.flightNotFound
        }
        return result
    }

    private func sendRPC(
        id: Int,
        method: String,
        params: [String: Any],
        apiKey: String,
        sessionID: String?
    ) async throws -> (body: Any, sessionID: String?) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if method != "initialize" {
            request.setValue("2025-03-26", forHTTPHeaderField: "MCP-Protocol-Version")
        }
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw VariFlightClientError.invalidResponse }
        let responseSessionID = http.value(forHTTPHeaderField: "Mcp-Session-Id") ?? sessionID
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let message: String
            switch http.statusCode {
            case 401: message = String(localized: "飞友 API 密钥无效，请检查设置。")
            case 403: message = String(localized: "飞友 API 余额不足或账户不可用，请检查控制台。")
            default: message = "飞友航班查询失败（HTTP \(http.statusCode)）\(detail.map { ": \($0)" } ?? "")."
            }
            throw VariFlightClientError.requestFailed(message)
        }
        return (try decodeMCPBody(data), responseSessionID)
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
        throw VariFlightClientError.requestFailed("飞友接口返回的内容不是可识别的 JSON/SSE：\(String(text.prefix(400)))")
    }

    private func appendSSEEvent(_ dataLines: [String], to events: inout [Any]) {
        guard !dataLines.isEmpty,
              let data = dataLines.joined(separator: "\n").data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return }
        events.append(json)
    }

    private func parseLookupResult(from response: Any) throws -> VariFlightLookupResult {
        if let batch = response as? [Any] {
            for item in batch {
                if let parsed = try? parseLookupResult(from: item) { return parsed }
            }
            throw VariFlightClientError.invalidResponse
        }
        guard let envelope = response as? [String: Any] else { throw VariFlightClientError.invalidResponse }
        if let error = envelope["error"] as? [String: Any] {
            let message = error["message"] as? String ?? String(localized: "飞友航班查询失败。")
            throw VariFlightClientError.requestFailed(message)
        }
        guard let result = envelope["result"] as? [String: Any] else {
            let excerpt = String(String(describing: envelope).prefix(400))
            throw VariFlightClientError.requestFailed("飞友接口响应缺少 MCP result 对象：\(excerpt)")
        }
        if (result["isError"] as? Bool) == true {
            let message = (result["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.first
                ?? String(localized: "飞友航班查询失败。")
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

        var extractedFields: [FlightField: String] = [:]
        for candidate in candidates {
            guard let extracted = fields(from: candidate) else { continue }
            for (field, value) in extracted where extractedFields[field] == nil { extractedFields[field] = value }
        }
        if !extractedFields.isEmpty {
            return VariFlightLookupResult(
                airlineName: extractedFields[.airline],
                departureAirport: extractedFields[.departureAirport],
                arrivalAirport: extractedFields[.arrivalAirport],
                departureTerminal: extractedFields[.departureTerminal],
                arrivalTerminal: extractedFields[.arrivalTerminal],
                departureTime: extractedFields[.departure],
                estimatedArrivalTime: extractedFields[.arrival],
                baggageCarousel: extractedFields[.baggage]
            )
        }
        let excerpt: String
        if let contents = result["content"] as? [[String: Any]],
           let text = contents.compactMap({ $0["text"] as? String }).first {
            excerpt = String(text.prefix(500))
        } else {
            excerpt = "result 字段：\(result.keys.sorted().joined(separator: ", "))"
        }
        throw VariFlightClientError.requestFailed("飞友接口已返回结果，但应用暂未识别其字段格式。响应片段：\(excerpt)")
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
        for nested in object.values {
            guard let parsed = fields(from: nested) else { continue }
            for (field, value) in parsed where result[field] == nil { result[field] = value }
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
