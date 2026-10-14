import Foundation
import Security

struct FlightAwareLookupResult {
    let departureTime: String?
    let estimatedArrivalTime: String?
    let arrivalTerminal: String?
    let baggageCarousel: String?
}

enum FlightAwareClientError: LocalizedError {
    case missingAPIKey, invalidFlightNumber, flightNotFound, requestFailed(String), invalidResponse
    var errorDescription: String? {
        switch self {
        case .missingAPIKey: String(localized: "请先在设置中保存 FlightAware API 密钥。")
        case .invalidFlightNumber: String(localized: "请输入有效的航班号。")
        case .flightNotFound: String(localized: "没有找到该日期的航班，请检查航班号和日期。")
        case .requestFailed(let message): message
        case .invalidResponse: "航班接口返回的数据无法识别。"
        }
    }
}

enum FlightAwareAPIKeyStore {
    private static let service = "com.yunshengtech.travelmanager.flightaware"
    private static let account = "aeroapi-key"

    static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
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
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

struct FlightAwareClient {
    func lookup(flightNumber: String, flightDate: Date) async throws -> FlightAwareLookupResult {
        guard let apiKey = FlightAwareAPIKeyStore.read(), !apiKey.isEmpty else { throw FlightAwareClientError.missingAPIKey }
        let ident = flightNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().filter { $0.isLetter || $0.isNumber }
        guard !ident.isEmpty else { throw FlightAwareClientError.invalidFlightNumber }

        let selected = Calendar.current.dateComponents([.year, .month, .day], from: flightDate)
        guard let localStart = Calendar.current.date(from: selected),
              let start = Calendar(identifier: .gregorian).date(byAdding: .hour, value: -12, to: localStart),
              let end = Calendar(identifier: .gregorian).date(byAdding: .hour, value: 36, to: localStart) else { throw FlightAwareClientError.invalidResponse }
        var urlComponents = URLComponents(string: "https://aeroapi.flightaware.com/aeroapi/flights/\(ident)")!
        let iso = ISO8601DateFormatter()
        urlComponents.queryItems = [URLQueryItem(name: "start", value: iso.string(from: start)), URLQueryItem(name: "end", value: iso.string(from: end)), URLQueryItem(name: "max_pages", value: "2")]
        guard let url = urlComponents.url else { throw FlightAwareClientError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FlightAwareClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw FlightAwareClientError.requestFailed(String(localized: "FlightAware API 密钥无效，请检查设置。")) }
            if http.statusCode == 402 || http.statusCode == 403 { throw FlightAwareClientError.requestFailed(String(localized: "当前 FlightAware 账户套餐不支持此查询，请检查账户权限。")) }
            throw FlightAwareClientError.requestFailed("FlightAware 查询失败（HTTP \(http.statusCode)）。")
        }
        let payload = try JSONDecoder.flightAware.decode(FlightsResponse.self, from: data)
        let flight = payload.flights.first { candidate in
            guard let departure = candidate.scheduledOut ?? candidate.estimatedOut,
                  let zoneID = candidate.origin?.timeZone,
                  let zone = TimeZone(identifier: zoneID) else { return false }
            var localCalendar = Calendar(identifier: .gregorian)
            localCalendar.timeZone = zone
            let localDate = localCalendar.dateComponents([.year, .month, .day], from: departure)
            return localDate.year == selected.year && localDate.month == selected.month && localDate.day == selected.day
        } ?? payload.flights.first
        guard let flight else { throw FlightAwareClientError.flightNotFound }
        return FlightAwareLookupResult(
            departureTime: format(flight.estimatedOff ?? flight.scheduledOff ?? flight.estimatedOut ?? flight.scheduledOut, timeZone: flight.origin?.timeZone),
            estimatedArrivalTime: format(flight.estimatedIn ?? flight.estimatedOn ?? flight.scheduledIn ?? flight.scheduledOn, timeZone: flight.destination?.timeZone),
            arrivalTerminal: flight.terminalDestination,
            baggageCarousel: flight.baggageClaim
        )
    }

    private func format(_ date: Date?, timeZone: String?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm zzz"
        return formatter.string(from: date)
    }
}

private struct FlightsResponse: Decodable { let flights: [Flight] }
private struct Flight: Decodable {
    let scheduledOut: Date?; let estimatedOut: Date?; let scheduledOff: Date?; let estimatedOff: Date?
    let scheduledOn: Date?; let estimatedOn: Date?; let scheduledIn: Date?; let estimatedIn: Date?
    let terminalDestination: String?; let baggageClaim: String?; let origin: Airport?; let destination: Airport?
    enum CodingKeys: String, CodingKey {
        case scheduledOut = "scheduled_out", estimatedOut = "estimated_out", scheduledOff = "scheduled_off", estimatedOff = "estimated_off"
        case scheduledOn = "scheduled_on", estimatedOn = "estimated_on", scheduledIn = "scheduled_in", estimatedIn = "estimated_in"
        case terminalDestination = "terminal_destination", baggageClaim = "baggage_claim", origin, destination
    }
}
private struct Airport: Decodable { let timeZone: String?; enum CodingKeys: String, CodingKey { case timeZone = "timezone" } }
private extension JSONDecoder {
    static var flightAware: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid AeroAPI timestamp")
        }
        return decoder
    }
}
