import XCTest
import SwiftUI
import StoreKitTest

/// UI fixture, not a payment assertion suite. All transactions are local; purchase buttons stay disabled.
@MainActor final class PurchaseUIOnlyTests: XCTestCase {
    func testPreview() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "TrvelMA", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.storefront = "USA"
        session.locale = Locale(identifier: "zh_Hans")
        let originalLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        UserDefaults.standard.set("zh-Hans", forKey: "appLanguage")
        defer { UserDefaults.standard.set(originalLanguage, forKey: "appLanguage") }
        let auth = AuthViewModel()
        auth.clearIsolatedTestSession()
        let finished = expectation(description: "Finish local purchase UI preview via QA button")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        let originalController = window.rootViewController
        defer { window.rootViewController = originalController }
        window.rootViewController = UIHostingController(rootView: PurchaseUIPreview(session: session, finish: { finished.fulfill() }).environment(auth))
        window.makeKeyAndVisible()
        await fulfillment(of: [finished], timeout: 600)
    }
}

private struct PurchaseUIPreview: View {
    let session: SKTestSession
    let finish: () -> Void
    @State private var language = "zh-Hans"
    var body: some View {
        VStack(spacing: 0) {
            Text("LOCAL STOREKIT · QA ONLY · NO PURCHASES").font(.caption2).foregroundStyle(.orange)
            HStack {
                Picker("QA Language", selection: $language) {
                    ForEach(AppLanguage.options) { Text($0.nativeName).tag($0.rawValue) }
                }.pickerStyle(.menu)
                Button("Finish QA preview", action: finish).font(.caption)
            }
            PurchasePlansView().environment(\.locale, Locale(identifier: language)).id(language)
        }
        .onChange(of: language) { _, value in
            UserDefaults.standard.set(value, forKey: "appLanguage")
            let storeLocale = ["en": "en_US", "es": "es_ES"][value] ?? value.replacingOccurrences(of: "-", with: "_")
            session.locale = Locale(identifier: storeLocale)
        }
    }
}
