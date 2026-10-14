//
//  User.swift
//  Wishlist
//
//  Created by Tony.W on 7/7/26.
//  Copyright © 2026 Apple. All rights reserved.
//

import Foundation
import SwiftData

// ==========================================
// 1. 登录信息表 (Account / LoginInfo)
// ==========================================
@Model
class LoginInfo {
    // 🌟 与服务器对接的关键：设置服务器用户ID为主键
    @Attribute(.unique) var serverUserId: String
    
    var username: String          // 登录账号（手机号或邮箱）
    var loginToken: String        // 服务器返回的身份验证令牌 (JWT Token)
    var tokenExpiredAt: Date      // Token 过期时间
    var lastLoginAt: Date         // 上次登录时间
    var isRemembered: Bool        // 是否记住登录状态
    
    // 🌟 一对一关联：一个账号对应一个详细的个人信息
    // deleteRule: .cascade 表示当用户注销/删除账号时，其个人信息也同步删除
    @Relationship(deleteRule: .cascade, inverse: \ProfileInfo.loginInfo)
    var profile: ProfileInfo?
    
    init(serverUserId: String, username: String, loginToken: String, tokenExpiredAt: Date, lastLoginAt: Date = Date(), isRemembered: Bool = true) {
        self.serverUserId = serverUserId
        self.username = username
        self.loginToken = loginToken
        self.tokenExpiredAt = tokenExpiredAt
        self.lastLoginAt = lastLoginAt
        self.isRemembered = isRemembered
    }
}

// ==========================================
// 2. 个人信息表 (ProfileInfo)
// ==========================================
@Model
class ProfileInfo {
    var nickname: String          // 昵称
    var avatarUrl: String         // 头像网络链接
    var gender: Int               // 性别：0-未知，1-男，2-女
    var birthday: Date?           // 生日（可选）
    var bio: String               // 个人简介
    var region: String            // 地区（如：北京 朝阳）
    var phone: String = ""
    var email: String = ""
    var weChatQrcode: String = ""
    var lineQrcode: String = ""
    var whatsAppQrcode: String = ""
    
    
    // 🌟 反向关联：指向所属的登录信息（必须是可选型）
    var loginInfo: LoginInfo?
    
    init(nickname: String, avatarUrl: String, gender: Int, birthday: Date? = nil, bio: String, region: String, phone: String, email: String, weChatQrcode: String, lineQrcode: String, whatsAppQrcode: String, loginInfo: LoginInfo? = nil) {
        self.nickname = nickname
        self.avatarUrl = avatarUrl
        self.gender = gender
        self.birthday = birthday
        self.bio = bio
        self.region = region
        self.phone = phone
        self.email = email
        self.weChatQrcode = weChatQrcode
        self.lineQrcode = lineQrcode
        self.whatsAppQrcode = whatsAppQrcode
        self.loginInfo = loginInfo
    }
}
