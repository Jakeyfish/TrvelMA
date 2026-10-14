//
//  Custumer.swift
//  Wishlist
//
//  Created by Tony.W on 7/6/26.
//  Copyright © 2026 Apple. All rights reserved.
//  客户信息表，支持多个地址信息和联系方式

import SwiftUI
import SwiftData
import Foundation

@Model
class Custumer {
    @Attribute(.unique) var uuid: String
    var version: Int = 1
    var syncState: Int = 0
    
    
    //核心数据项
    var name: String                //客户名称
    var email: String               //客户email
    var avatarUrl: String = ""     // 用户头像的网络 URL 地址
    var csource: String             //客户来源 例如 1-普通 2-中价 3-旅行社
    var type: Int                   //客户类型 例如 1-普通 2-VIP
    var customerCategory: Int = 1    //客户类别：1-普通客户 2-旅行社
    var languagePreference: String = "zh-Hans"
    var remark: String = ""
    var createdAt: Date             //客户建立日期
    var updateAt: Date
    
    
    @Relationship(deleteRule: .cascade, inverse: \Address.customer)
    var addresses: [Address] = [] // 必须初始化为空数组
    
    
    @Relationship(deleteRule: .cascade, inverse: \Connect.customer)
    var connecttype: [Connect] = [] // 必须初始化为空数组
    
    init(
        uuid: String = UUID().uuidString.lowercased(),
        version: Int = 1,
        syncState: Int = 0,
        name: String,
        email: String,
        avatarUrl: String = "",
        csource: String,
        type: Int,
        customerCategory: Int = 1,
        languagePreference: String = "zh-Hans",
        remark: String = "",
        createdAt: Date = Date(),
        updateAt: Date = Date()
    ){
        self.uuid = uuid
        self.version = version
        self.syncState = syncState
        self.name = name
        self.email = email
        self.avatarUrl = avatarUrl
        self.csource = csource
        self.type = type
        self.customerCategory = customerCategory
        self.languagePreference = languagePreference
        self.remark = remark
        self.createdAt = createdAt
        self.updateAt = updateAt
    }
}


@Model
class Address{
    var addlable: String
    var addresses :String
    var isDefault: Bool = false
    
    var customer: Custumer?
    
    init(addlable: String, addresses: String, isDefault: Bool = false, customer: Custumer) {
        self.addlable = addlable
        self.addresses = addresses
        self.isDefault = isDefault
        self.customer = customer
    }
    
 }

@Model
class Connect{
    var connectlable: String
    var connecttype: String
    var isDefault: Bool = false
    
    
    var customer: Custumer?
    
    init(connectlable: String, connecttype: String, isDefault: Bool = false, customer: Custumer) {
        self.connectlable = connectlable
        self.connecttype = connecttype
        self.isDefault = isDefault
        self.customer = customer
    }
}
