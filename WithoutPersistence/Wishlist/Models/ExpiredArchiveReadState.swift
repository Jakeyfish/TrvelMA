import Foundation

/// Memory-only read state. Never grants access or retains an archive across owners.
struct ExpiredArchiveReadState {
    private(set) var owner = ""
    private var requestID: UUID?
    private(set) var snapshot: [String: Any] = [:]
    private(set) var exportData = Data()
    private(set) var busy = false
    private var needsRefresh = true
    var canExport: Bool { !busy && !needsRefresh && !exportData.isEmpty }

    func isCurrent(request: UUID, owner: String) -> Bool { requestID == request && self.owner == owner }

    mutating func begin(owner: String) -> UUID {
        if self.owner != owner { reset(); self.owner = owner }
        let id = UUID(); requestID = id; busy = true; needsRefresh = true
        return id
    }
    mutating func accept(_ data: Data, request: UUID, owner: String) throws {
        guard requestID == request, self.owner == owner else { return }
        guard let archive = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              archive["read_only"] as? Bool == true else { throw InvalidArchive() }
        let export = try JSONSerialization.data(withJSONObject: archive, options: [.prettyPrinted, .sortedKeys])
        snapshot = archive; exportData = export; busy = false; needsRefresh = false; requestID = nil
    }
    mutating func fail(request: UUID, owner: String, transient: Bool) {
        guard requestID == request, self.owner == owner else { return }
        if !transient { snapshot = [:]; exportData = Data() }
        busy = false; needsRefresh = true; requestID = nil
    }
    mutating func reset() {
        owner = ""; requestID = nil; snapshot = [:]; exportData = Data(); busy = false; needsRefresh = true
    }
    struct InvalidArchive: Error {}
}
