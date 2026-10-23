/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The main app structure.
*/

import SwiftUI
import SwiftData
import UserNotifications
import UIKit

extension View {
    func adaptiveFormPresentation<PresentedContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> PresentedContent
    ) -> some View {
        modifier(AdaptiveFormPresentationModifier(isPresented: isPresented, presentedContent: content))
    }

    func adaptiveItemFormPresentation<Item: Identifiable, PresentedContent: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> PresentedContent
    ) -> some View {
        modifier(AdaptiveItemFormPresentationModifier(item: item, presentedContent: content))
    }
}

private struct AdaptiveFormPresentationModifier<PresentedContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let presentedContent: () -> PresentedContent

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    func body(content base: Content) -> some View {
        base
            .sheet(isPresented: Binding(
                get: { !isPad && isPresented },
                set: { if !$0 { isPresented = false } }
            ), content: presentedContent)
            .fullScreenCover(isPresented: Binding(
                get: { isPad && isPresented },
                set: { if !$0 { isPresented = false } }
            ), content: presentedContent)
    }
}

private struct AdaptiveItemFormPresentationModifier<Item: Identifiable, PresentedContent: View>: ViewModifier {
    @Binding var item: Item?
    @ViewBuilder let presentedContent: (Item) -> PresentedContent

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    func body(content base: Content) -> some View {
        base
            .sheet(item: Binding(
                get: { isPad ? nil : item },
                set: { if $0 == nil { item = nil } }
            ), content: presentedContent)
            .fullScreenCover(item: Binding(
                get: { isPad ? item : nil },
                set: { if $0 == nil { item = nil } }
            ), content: presentedContent)
    }
}

final class WishlistApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .allButUpsideDown : .portrait
    }
}

@main
struct WishlistApp: App {
    @UIApplicationDelegateAdaptor(WishlistApplicationDelegate.self) private var applicationDelegate

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


