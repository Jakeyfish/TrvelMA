import XCTest
import SwiftUI

/// Isolated rendering of the shipping flight panel, not a live flight lookup.
@MainActor final class MarketingFlightPreviewTests: XCTestCase {
    func testPreview() async throws {
        let oldLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        UserDefaults.standard.set("zh-Hans", forKey: "appLanguage")
        defer { UserDefaults.standard.set(oldLanguage, forKey: "appLanguage") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        let previous = window.rootViewController
        defer { window.rootViewController = previous }
        let finish = expectation(description: "Close flight panel preview")
        window.rootViewController = UIHostingController(rootView: MarketingFlightPanelPreview(finish: { finish.fulfill() }))
        window.makeKeyAndVisible()
        print("MARKETING_FLIGHT_READY")
        await fulfillment(of: [finish], timeout: 600)
    }
}

private struct MarketingFlightPanelPreview: View {
    let finish: () -> Void
    private let sample = VariFlightLookupResult(airlineName: "星宇航空", departureAirport: "台北桃园 TPE", arrivalAirport: "洛杉矶 LAX", departureTerminal: "T1", arrivalTerminal: "TBIT", departureTime: "23:40", estimatedArrivalTime: "19:00", baggageCarousel: nil)
    var body: some View {
        NavigationStack {
            ScrollView {
                FlightInformationPanel(flightNumber: "JX2", flightDate: Date(timeIntervalSince1970: 1795564800), result: sample, isLoading: false, error: nil, departureFallback: "23:40", arrivalFallback: "19:00", departureTimeZone: "GMT+8", arrivalTimeZone: "GMT−8")
                    .padding(24)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                    .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("航班信息")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: finish) } }
        }
        .tint(Color(red: 0.40, green: 0.31, blue: 0.95))
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .preferredColorScheme(.light)
    }
}
