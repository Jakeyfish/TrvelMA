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
final class TravelAgency {
    @Attribute(.unique) var uuid: String
    var ownerScope: String = "local"
    var agencyCode: String
    var name: String
    var contactPerson: String
    var phone: String
    var officeAddress: String
    var createdAt: Date
    var updateAt: Date
    /// Cloud timestamp last confirmed by a successful download or upload.
    var syncBaseUpdatedAt: Date? = nil

    init(
        uuid: String = UUID().uuidString.lowercased(),
        agencyCode: String,
        name: String,
        contactPerson: String = "",
        phone: String = "",
        officeAddress: String = "",
        createdAt: Date = .now,
        updateAt: Date = .now,
        syncBaseUpdatedAt: Date? = nil
    ) {
        self.uuid = uuid
        self.ownerScope = DataOwnership.activeScope
        self.agencyCode = agencyCode
        self.name = name
        self.contactPerson = contactPerson
        self.phone = phone
        self.officeAddress = officeAddress
        self.createdAt = createdAt
        self.updateAt = updateAt
        self.syncBaseUpdatedAt = syncBaseUpdatedAt
    }
}

@Model
class Custumer {
    @Attribute(.unique) var uuid: String
    var ownerScope: String = "local"
    var version: Int = 1
    var syncState: Int = 0
    
    
    //核心数据项
    var name: String                //客户名称
    var email: String               //客户email
    var avatarUrl: String = ""     // 用户头像的网络 URL 地址
    var csource: String             //客户来源 例如 1-普通 2-中价 3-旅行社
    var type: Int                   //客户类型 例如 1-普通 2-VIP
    var customerCategory: Int = 1    //客户类别：1-普通客户 2-旅行社
    var travelAgencyCode: String = ""
    var travelAgencyName: String = ""
    var languagePreference: String = "zh-Hans"
    var remark: String = ""
    var createdAt: Date             //客户建立日期
    var updateAt: Date
    /// Cloud timestamp last confirmed by a successful download or upload.
    var syncBaseUpdatedAt: Date? = nil
    
    
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
        travelAgencyCode: String = "",
        travelAgencyName: String = "",
        languagePreference: String = "zh-Hans",
        remark: String = "",
        createdAt: Date = Date(),
        updateAt: Date = Date(),
        syncBaseUpdatedAt: Date? = nil
    ){
        self.uuid = uuid
        self.ownerScope = DataOwnership.activeScope
        self.version = version
        self.syncState = syncState
        self.name = name
        self.email = email
        self.avatarUrl = avatarUrl
        self.csource = csource
        self.type = type
        self.customerCategory = customerCategory
        self.travelAgencyCode = travelAgencyCode
        self.travelAgencyName = travelAgencyName
        self.languagePreference = languagePreference
        self.remark = remark
        self.createdAt = createdAt
        self.updateAt = updateAt
        self.syncBaseUpdatedAt = syncBaseUpdatedAt
    }
}


@Model
class Address{
    var ownerScope: String = "local"
    var addlable: String
    var addresses :String
    var isDefault: Bool = false
    
    var customer: Custumer?
    
    init(addlable: String, addresses: String, isDefault: Bool = false, customer: Custumer) {
        self.addlable = addlable
        self.ownerScope = customer.ownerScope
        self.addresses = addresses
        self.isDefault = isDefault
        self.customer = customer
    }
    
 }

@Model
class Connect{
    var ownerScope: String = "local"
    var connectlable: String
    var connecttype: String
    var isDefault: Bool = false
    
    
    var customer: Custumer?
    
    init(connectlable: String, connecttype: String, isDefault: Bool = false, customer: Custumer) {
        self.connectlable = connectlable
        self.ownerScope = customer.ownerScope
        self.connecttype = connecttype
        self.isDefault = isDefault
        self.customer = customer
    }
}
