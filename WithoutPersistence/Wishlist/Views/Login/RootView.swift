//
//  RootView.swift
//  Wishlist
//
//  Created by Tony.W on 6/10/26.
//  Copyright © 2026 Apple. All rights reserved.
//


import SwiftUI

//struct RootView: View {
//
//    @Environment(AuthViewModel.self)
//    private var auth
//
//    var body: some View {
//
//        if auth.isLoggedIn {
//
//            ContentView()
//
//        } else {
//
//            LoginView()
//        }
//    }
//}


struct RootView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {

        if auth.isLoggedIn {

            ContentView()

        } else {
            LoginView()
        }
    }
}


//
//#Preview {
//    @Previewable @State var dataSource = DataSource()
//
//        RootView()
//        .environment(dataSource)
//}
