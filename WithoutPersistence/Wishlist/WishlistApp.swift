/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The main app structure.
*/

import SwiftUI
import SwiftData
import UserNotifications

@main
struct WishlistApp: App {

    init() {
        UNUserNotificationCenter.current().delegate = TripNotificationDelegate.shared
    }

    @Environment(\.scenePhase) private var scenePhase

    /// The data source provides trip data to this view and its descendants.
    @State private var dataSource = DataSource()
    @State private var auth = AuthViewModel()
    @State private var languageSettings = AppLanguageSettings()
    @State private var dataStore = AppDataContainerManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(dataStore)
                .environment(languageSettings)
                .environment(\.locale, languageSettings.locale)
                .modelContainer(dataStore.activeContainer)
               .environment(dataSource)
               .onChange(of: scenePhase) { _, newPhase in
                   if newPhase == .active {
                       auth.refreshSessionIfNeeded()
                   }
               }
        }
        
        
        
        
        
        
        
    }
}


