import SwiftUI
import UIKit

extension View {
    /// Uses the system keyboard without inheriting the app's selected display language.
    func nativeIMEInput() -> some View {
        keyboardType(.default)
            .environment(\.locale, Locale.autoupdatingCurrent)
    }
}
