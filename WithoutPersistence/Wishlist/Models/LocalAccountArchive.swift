import Foundation
import SwiftData

/// Explicit business-data allowlist. Never serialize authentication models or defaults wholesale.
@MainActor enum LocalAccountArchive {
    enum Failure: Error { case wrongScope }

    static func snapshot(context: ModelContext, email: String) throws -> [String: Any] {
        let scope = DataOwnership.localScope(email: email)
        guard DataOwnership.activeScope == scope, DataOwnership.isLocalScope(scope) else { throw Failure.wrongScope }
        let trips = try context.fetch(FetchDescriptor<TripBookingRecord>(predicate: #Predicate { $0.ownerScope == scope }))
        let customers = try context.fetch(FetchDescriptor<Custumer>(predicate: #Predicate { $0.ownerScope == scope }))
        let agencies = try context.fetch(FetchDescriptor<TravelAgency>(predicate: #Predicate { $0.ownerScope == scope }))
        let formatter = ISO8601DateFormatter()
        func date(_ value: Date?) -> Any { value.map { formatter.string(from: $0) } ?? NSNull() }
        let tripRows: [[String: Any]] = trips.sorted { $0.id.uuidString < $1.id.uuidString }.map { trip in
            var row: [String: Any] = ["id": trip.id.uuidString, "service_type": trip.serviceType,
                "order_source": trip.orderSource, "travel_agency_code": trip.travelAgencyCode,
                "travel_agency_name": trip.travelAgencyName, "travel_agency_order_number": trip.travelAgencyOrderNumber,
                "customer_name": trip.customerName, "customer_contact": trip.customerContact,
                "customer_count": trip.customerCount, "customer_stuff": trip.customerStuff]
            // A stale cross-owner relationship must not expose another account's identifier.
            row["customer_id"] = trip.customerUUID.flatMap { id in customers.contains { $0.uuid == id } ? id : nil } ?? ""
            row["appointment_date"] = date(trip.appointmentDate); row["appointment_time"] = date(trip.appointmentTime)
            row["location_start"] = trip.locationStart; row["location_end"] = trip.locationEnd
            row["location_stop"] = trip.locationStop; row["additional_stops_json"] = trip.additionalStopsJSON
            row["flight_info"] = trip.flightInfo; row["flight_date"] = date(trip.flightDate)
            row["flight_departure_time"] = trip.flightDepartureTime ?? ""
            row["flight_estimated_arrival_time"] = trip.flightEstimatedArrivalTime ?? ""
            row["flight_arrival_terminal"] = trip.flightArrivalTerminal ?? ""
            row["flight_baggage_carousel"] = trip.flightBaggageCarousel ?? ""
            row["flight_selection_snapshot_json"] = trip.flightSelectionSnapshotJSON
            row["memo"] = trip.memo; row["price"] = trip.price; row["tip"] = trip.tip
            row["expense_adjustments_json"] = trip.expenseAdjustmentsJSON
            row["is_paid"] = trip.isPaid; row["is_completed"] = trip.isCompleted; row["is_cancelled"] = trip.isCancelled
            row["reminder_enabled"] = trip.reminderEnabled; row["reminder_at"] = date(trip.reminderDateTime)
            row["has_second_reminder"] = trip.hasSecondReminder; row["second_reminder_at"] = date(trip.secondReminderDateTime)
            row["created_at"] = date(trip.createdAt); row["updated_at"] = date(trip.updatedAt)
            return row
        }
        let customerRows: [[String: Any]] = customers.sorted { $0.uuid < $1.uuid }.map { customer in
            var row: [String: Any] = ["id": customer.uuid, "name": customer.name, "email": customer.email,
                "avatar_url": customer.avatarUrl, "source": customer.csource, "type": customer.type,
                "category": customer.customerCategory, "travel_agency_code": customer.travelAgencyCode,
                "travel_agency_name": customer.travelAgencyName, "language": customer.languagePreference,
                "memo": customer.remark, "created_at": date(customer.createdAt), "updated_at": date(customer.updateAt)]
            row["contacts"] = customer.connecttype.filter { $0.ownerScope == scope && $0.customer?.uuid == customer.uuid }.map {
                ["label": $0.connectlable, "value": $0.connecttype, "is_default": $0.isDefault] as [String: Any]
            }
            row["addresses"] = customer.addresses.filter { $0.ownerScope == scope && $0.customer?.uuid == customer.uuid }.map {
                ["label": $0.addlable, "address": $0.addresses, "is_default": $0.isDefault] as [String: Any]
            }
            return row
        }
        let agencyRows: [[String: Any]] = agencies.sorted { $0.uuid < $1.uuid }.map {
            ["id": $0.uuid, "name": $0.name, "agency_code": $0.agencyCode, "contact_person": $0.contactPerson,
             "phone": $0.phone, "address": $0.officeAddress, "created_at": date($0.createdAt), "updated_at": date($0.updateAt)]
        }
        var assets: [String: String] = [:]
        for asset in AccountAssetStore.Asset.allCases {
            if let data = AccountAssetStore.data(for: asset, email: email, namespace: .local) {
                assets[asset.cloudColumn] = data.base64EncodedString()
            }
        }
        return ["format": "TrvelMA.local-business-archive", "version": 1, "read_only": true,
                "exported_at": date(.now), "trips": tripRows, "customers": customerRows,
                "travel_agencies": agencyRows, "local_assets_base64": assets]
    }
}
