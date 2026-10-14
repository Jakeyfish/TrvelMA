//
//  ProfileView.swift
//  Wishlist
//
//  Created by Tony.W on 6/10/26.
//  Copyright © 2026 Apple. All rights reserved.
//


import SwiftUI

struct ProfileView: View {

    @Environment(AuthViewModel.self)
    private var auth

    var body: some View {

        Form {

            Section {

                if auth.currentEmail.isEmpty {
                    Text("我的账号")
                } else {
                    Text(auth.currentEmail)
                }
                Text(auth.currentEmail)
            }

            Button("退出登录") {

                auth.logout()
            }
        }
        .navigationTitle("我的")
    }
}


//#Preview {
//    @Previewable @State var dataSource = DataSource()
//    ProfileView()
//        .environment(dataSource) // 🛠️ 必须在此处注入，Canvas 才能显示
//}
