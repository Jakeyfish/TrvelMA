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
    static let currentFormatVersion = 2

    let flightNumber: String
    let flightDate: String
    let selected: VariFlightLookupResult
    let fetchedAt: Date
    /// Missing on snapshots saved by the older terminal parser. Those cached
    /// results must be queried again so a departure terminal is not reused as
    /// the arrival terminal.
    let formatVersion: Int?

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
        self.formatVersion = Self.currentFormatVersion
    }

    func matches(flightNumber: String, flightDate: Date) -> Bool {
        let current = SavedFlightSelection(flightNumber: flightNumber, flightDate: flightDate, selected: selected, fetchedAt: fetchedAt)
        return formatVersion == Self.currentFormatVersion
            && self.flightNumber == current.flightNumber
            && self.flightDate == current.flightDate
    }
}

private struct AirportCodeCrosswalkFile: Decodable {
    let airports: [AirportCodeCrosswalkAirport]
}

private struct AirportCodeCrosswalkAirport: Decodable {
    let iataCode: String
    let name: String
    let municipality: String
    let keywords: [String]
}

struct FlightCandidatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let candidates: [VariFlightLookupResult]
    let onSelect: (VariFlightLookupResult) -> Void

    private var preferredHeight: CGFloat {
        min(184 + CGFloat(candidates.count) * 112, 660)
    }

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
            .presentationDetents([.height(preferredHeight)])
            .presentationDragIndicator(.visible)
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
    // OurAirports public-domain scheduled-service airport data, bundled locally
    // so route matching works offline and does not add provider API requests.
    private static let airportCodeCrosswalk: [AirportCodeCrosswalkAirport] = {
        guard let url = Bundle.main.url(forResource: "AirportCodeCrosswalk", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode(AirportCodeCrosswalkFile.self, from: data).airports) ?? []
    }()

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
        forceRefresh: Bool = false,
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
            sessionID: nil,
            forceRefresh: forceRefresh
        )

        return try parseLookupResults(from: response.body)
    }

    private func sendRPC(
        id: Int,
        method: String,
        params: [String: Any],
        apiKey: String?,
        cloudAccessToken: String?,
        sessionID: String?,
        forceRefresh: Bool
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
            var body: [String: Any] = [
                "flightNumber": arguments["fnum"] ?? "",
                "flightDate": arguments["date"] ?? "",
                "forceRefresh": forceRefresh
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
        cloudAccessToken: String? = nil,
        forceRefresh: Bool = false
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
            cloudAccessToken: cloudAccessToken,
            forceRefresh: forceRefresh
        )
        guard let airportHint else { return initial }

        var supplemental: [VariFlightLookupResult] = []
        // Avoid spending an extra provider lookup when the broad response already
        // contains a leg touching the trip's explicit airport. Keep the filtered
        // fallback for providers that omit that endpoint from broad searches.
        let initialContainsRequestedAirport = initial.contains { candidate in
            let airport = airportHint.isArrival ? candidate.arrivalAirport : candidate.departureAirport
            return Self.airportCodes(in: airport).contains(airportHint.code)
        }
        if !initialContainsRequestedAirport {
            supplemental += (try? await lookupCandidates(
                flightNumber: flightNumber,
                flightDate: flightDate,
                cloudAccessToken: cloudAccessToken,
                forceRefresh: forceRefresh,
                departureAirport: airportHint.isArrival ? nil : airportHint.code,
                arrivalAirport: airportHint.isArrival ? airportHint.code : nil
            )) ?? []
        }

        // Some provider responses contain a first leg to a connecting city and a
        // separate full-itinerary summary. Query each detected connection airport
        // to the requested arrival airport so the actual later leg can be selected.
        if airportHint.isArrival {
            let connectionCodes = Set((initial + supplemental).flatMap { candidate in
                Self.airportCodes(in: candidate.arrivalAirport).filter { $0 != airportHint.code }
            })
            for connectionCode in connectionCodes.sorted() {
                supplemental += (try? await lookupCandidates(
                    flightNumber: flightNumber,
                    flightDate: flightDate,
                    cloudAccessToken: cloudAccessToken,
                    forceRefresh: forceRefresh,
                    // Search by the connection airport alone. The provider's
                    // combined dep+arr filter can omit a selectable leg even
                    // when the unfiltered flight-number result contains it.
                    departureAirport: connectionCode
                )) ?? []
            }
        }

        var seen = Set<String>()
        let candidates = (initial + supplemental).filter { seen.insert($0.id).inserted }

        // A one-result response is not necessarily the trip's flight leg: some
        // provider responses return only the first leg of a multi-leg itinerary.
        // Keep only candidates that match the explicit airport in the trip route
        // so callers can never silently save an unrelated connecting leg.
        let matchingCandidates = candidates.filter { candidate in
            let airport = airportHint.isArrival ? candidate.arrivalAirport : candidate.departureAirport
            return Self.airportCodes(in: airport).contains(airportHint.code)
        }
        guard !matchingCandidates.isEmpty else { throw VariFlightClientError.flightNotFound }
        return matchingCandidates
    }

    static func candidateMatchesTripRoute(
        _ candidate: VariFlightLookupResult,
        serviceType: String,
        locationStart: String,
        locationEnd: String
    ) -> Bool {
        let airportHint: (code: String, isArrival: Bool)?
        if serviceType == "接机", let code = explicitAirportCode(in: locationStart) {
            airportHint = (code, true)
        } else if serviceType == "送机", let code = explicitAirportCode(in: locationEnd) {
            airportHint = (code, false)
        } else {
            airportHint = nil
        }
        guard let airportHint else { return true }
        let airport = airportHint.isArrival ? candidate.arrivalAirport : candidate.departureAirport
        return airportCodes(in: airport).contains(airportHint.code)
    }

    static func requiresExplicitFlightChoice(
        serviceType: String,
        locationStart: String,
        locationEnd: String
    ) -> Bool {
        if serviceType == "接机" { return explicitAirportCode(in: locationStart) != nil }
        if serviceType == "送机" { return explicitAirportCode(in: locationEnd) != nil }
        return false
    }

    private static func normalizedAirportCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return code.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) == nil ? nil : code
    }

    private static func explicitAirportCode(in location: String) -> String? {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.uppercased()
        // In pickup/drop-off route fields, a bare IATA code is already an explicit airport choice.
        if normalized.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) != nil {
            return normalized
        }
        if normalized.range(of: #"\b(?:AIRPORT|TERMINAL)\b|机场|航站楼|航站"#, options: .regularExpression) != nil {
            let codes = knownAirportCodes(for: trimmed)
            if codes.count == 1 { return codes.first }
        }
        // Require airport context so ordinary three-letter words in addresses are not treated as IATA codes.
        guard normalized.range(of: #"\b[A-Z]{3}\b.{0,24}\b(?:AIRPORT|TERMINAL|机场)\b|\b(?:AIRPORT|机场).{0,24}\b[A-Z]{3}\b"#, options: .regularExpression) != nil,
              let match = trimmed.range(of: #"\b[A-Z]{3}\b"#, options: .regularExpression) else { return nil }
        return String(trimmed[match])
    }

    private static func airportCode(in value: String?) -> String? {
        let codes = airportCodes(in: value)
        return codes.count == 1 ? codes.first : nil
    }

    private static func airportCodes(in value: String?) -> Set<String> {
        guard let value else { return [] }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^[A-Za-z]{3}$"#, options: .regularExpression) != nil {
            return [trimmed.uppercased()]
        }
        // Only accept uppercase tokens as IATA codes. Uppercasing the whole label first
        // turns the ordinary word “Los” into a false code (“LOS”).
        let patterns = [#"\(([A-Z]{3})\)"#, #"(?<![A-Za-z])([A-Z]{3})(?![A-Za-z])"#]
        for pattern in patterns {
            guard let match = trimmed.range(of: pattern, options: .regularExpression) else { continue }
            let code = String(trimmed[match]).filter(\.isLetter)
            if code.count == 3 { return [code] }
        }
        return knownAirportCodes(for: trimmed)
    }

    /// Maps airport labels and city-only labels to IATA codes. City aliases can
    /// intentionally map to more than one code (for example, Houston has IAH
    /// and HOU), so connection supplementation searches each plausible airport.
    private static func knownAirportCodes(for value: String) -> Set<String> {
        let normalized = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let aliases: [(names: [String], codes: Set<String>)] = [
            (["george bush intercontinental", "george bush", "乔治布什", "乔治布什洲际机场", "iah"], ["IAH"]),
            (["houston hobby", "hobby airport", "william p. hobby", "霍比机场", "霍比"], ["HOU"]),
            (["houston", "休斯敦", "休士顿"], ["IAH", "HOU"]),
            (["los angeles international", "los angeles airport", "洛杉矶国际机场", "洛杉矶机场", "洛杉矶"], ["LAX"]),
            (["john f. kennedy", "john f kennedy", "kennedy airport", "肯尼迪机场", "jfk"], ["JFK"]),
            (["la guardia", "拉瓜迪亚机场", "lga"], ["LGA"]),
            (["newark liberty", "newark airport", "纽瓦克机场", "ewr"], ["EWR"]),
            (["new york", "纽约"], ["JFK", "LGA", "EWR"]),
            (["heathrow", "希思罗机场", "lhr"], ["LHR"]),
            (["gatwick", "盖特威克机场", "lgw"], ["LGW"]),
            (["stansted", "斯坦斯特德机场", "stn"], ["STN"]),
            (["london", "伦敦"], ["LHR", "LGW", "STN", "LTN", "LCY"]),
            (["tokyo haneda", "haneda", "羽田机场", "hnd"], ["HND"]),
            (["narita", "成田机场", "nrt"], ["NRT"]),
            (["tokyo", "东京"], ["HND", "NRT"]),
            (["charles de gaulle", "戴高乐机场", "cdg"], ["CDG"]),
            (["orly", "奥利机场", "ory"], ["ORY"]),
            (["paris", "巴黎"], ["CDG", "ORY"]),
            (["dulles", "杜勒斯机场", "iad"], ["IAD"]),
            (["reagan national", "里根国家机场", "dca"], ["DCA"]),
            (["washington", "华盛顿"], ["IAD", "DCA", "BWI"]),
            (["o'hare", "ohare", "奥黑尔机场", "ord"], ["ORD"]),
            (["midway", "中途机场", "mdw"], ["MDW"]),
            (["chicago", "芝加哥"], ["ORD", "MDW"]),
            (["san francisco international", "旧金山国际机场", "sfo"], ["SFO"]),
            (["oakland international", "奥克兰国际机场", "oak"], ["OAK"]),
            (["san jose international", "圣何塞国际机场", "sjc"], ["SJC"]),
            (["san francisco bay area", "san francisco", "旧金山"], ["SFO", "OAK", "SJC"]),
            (["dallas fort worth", "达拉斯沃斯堡", "dfw"], ["DFW"]),
            (["love field", "达拉斯爱田", "dal"], ["DAL"]),
            (["dallas", "达拉斯"], ["DFW", "DAL"]),
            (["incheon", "仁川机场", "icn"], ["ICN"]),
            (["gimpo", "金浦机场", "gmp"], ["GMP"]),
            (["seoul", "首尔"], ["ICN", "GMP"]),
            (["kansai international", "关西国际机场", "kix"], ["KIX"]),
            (["osaka international", "伊丹机场", "itm"], ["ITM"]),
            (["osaka", "大阪"], ["KIX", "ITM"]),
            (["malpensa", "马尔彭萨机场", "mxp"], ["MXP"]),
            (["linate", "利纳特机场", "lin"], ["LIN"]),
            (["milan", "米兰"], ["MXP", "LIN"]),
            (["fiumicino", "菲乌米奇诺机场", "fco"], ["FCO"]),
            (["ciampino", "钱皮诺机场", "cia"], ["CIA"]),
            (["rome", "罗马"], ["FCO", "CIA"]),
            (["istanbul airport", "伊斯坦布尔机场", "ist"], ["IST"]),
            (["sabiha gokcen", "萨比哈格克琴机场", "saw"], ["SAW"]),
            (["istanbul", "伊斯坦布尔"], ["IST", "SAW"]),
            (["taoyuan", "桃园机场", "tpe"], ["TPE"]),
            (["songshan", "松山机场", "tsa"], ["TSA"]),
            (["taipei", "台北"], ["TPE", "TSA"]),
            (["pearson", "皮尔逊机场", "yyz"], ["YYZ"]),
            (["billy bishop", "比利毕晓普机场", "ytz"], ["YTZ"]),
            (["toronto", "多伦多"], ["YYZ", "YTZ"]),
            (["beijing capital", "首都机场", "pek"], ["PEK"]),
            (["beijing daxing", "大兴机场", "pkx"], ["PKX"]),
            (["beijing", "北京"], ["PEK", "PKX"]),
            (["pudong", "浦东机场", "pvg"], ["PVG"]),
            (["hongqiao", "虹桥机场", "sha"], ["SHA"]),
            (["shanghai", "上海"], ["PVG", "SHA"]),
        ]
        var matches = aliases.compactMap { entry -> (length: Int, codes: Set<String>)? in
            let matchedName = entry.names
                .filter { normalized.contains($0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)) }
                .map(\.count)
                .max()
            guard let matchedName else { return nil }
            return (matchedName, entry.codes)
        }
        let datasetMatches = airportCodeCrosswalk.compactMap { airport -> (length: Int, codes: Set<String>)? in
            let aliases = [airport.name, airport.municipality] + airport.keywords
            let matchedName = aliases
                .map { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
                .filter { $0.count >= 4 && normalized.contains($0) }
                .map(\.count)
                .max()
            guard let matchedName else { return nil }
            return (matchedName, [airport.iataCode])
        }
        matches += datasetMatches
        guard let longest = matches.map(\.length).max() else { return [] }
        return matches.filter { $0.length == longest }.reduce(into: Set<String>()) { $0.formUnion($1.codes) }
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
            throw VariFlightClientError.requestFailed(localizedProviderError(message))
        }
        guard let result = envelope["result"] as? [String: Any] else {
            let excerpt = String(String(describing: envelope).prefix(400))
            let format = String(localized: "飞友接口响应缺少 MCP result 对象：%@", locale: AppLanguageSettings.currentLocale)
            throw VariFlightClientError.requestFailed(String(format: format, locale: AppLanguageSettings.currentLocale, arguments: [excerpt]))
        }
        if (result["isError"] as? Bool) == true {
            let message = (result["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.first
                ?? String(localized: "飞友航班查询失败。", locale: AppLanguageSettings.currentLocale)
            throw VariFlightClientError.requestFailed(localizedProviderError(message))
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

    private func localizedProviderError(_ message: String) -> String {
        let normalized = message.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if normalized.contains("api key is disabled") || normalized.contains("api key 已停用") {
            return String(localized: "飞友 API 密钥已停用，请在飞友控制台启用或更换。", locale: AppLanguageSettings.currentLocale)
        }
        return message
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
            // VariFlight's unqualified `terminal` field describes the origin terminal.
            // Do not put it in the arrival slot: for UA1743 this is IAH Terminal C,
            // while LAX's arrival terminal is reported separately as Terminal 7.
            case "flightdeptterminal", "flightdeptterminalname", "departureterminal", "departureterminalname", "depterminal", "terminaldeparture", "deptterminal", "terminal":
                if result[.departureTerminal] == nil { result[.departureTerminal] = string }
            case "flightarrterminal", "flightarrterminalname", "arrivalterminal", "arrivalterminalname", "arrterminal", "arrterminalname", "terminalarrival", "terminalarr", "arriveterminal":
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
            (.departureTerminal, #"(?:FlightDeptTerminal(?:Name)?|departureTerminalName|depTerminalName|出发航站楼|出发航站|departure\s*terminal|dep\s*terminal|(?<!arrival )(?<!arr )(?<!到达)(?<![A-Za-z])terminal)\s*[\"']?\s*[:：]\s*[\"']?([^\"'\n,，;；}]+)"#),
            (.arrivalTerminal, #"(?:FlightArrTerminal(?:Name)?|arrivalTerminalName|arrTerminalName|到达航站楼|到达航站|到达航站区|arrival\s*terminal|arr\s*terminal)\s*[\"']?\s*[:：]\s*[\"']?([^\"'\n,，;；}]+)"#),
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
