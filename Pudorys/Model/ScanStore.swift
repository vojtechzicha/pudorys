import Foundation
import Observation
import UIKit

struct PhotoRecord: Codable, Hashable, Identifiable {
    var id: String
    var fileName: String
    /// Where the phone was when the photo was taken (plan coordinates), if taken during the scan.
    var position: P2?
    /// Viewing direction on the plan, degrees clockwise from +x.
    var heading: Double?
    var takenAt: Date
    var caption: String = ""
}

struct ChatTurn: Codable, Hashable, Identifiable {
    enum Role: String, Codable { case user, assistant, error }
    var id = UUID()
    var role: Role
    var text: String
    var suggestions: [String] = []
    var hasLayout = false
}

struct ChatState: Codable {
    var turns: [ChatTurn] = []
    /// Messages exactly as exchanged with the API, replayed on every request.
    var apiMessages: [JSONValue] = []
}

struct ScanRecord: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var createdAt: Date
    var plan: PlanModel
    var photos: [PhotoRecord] = []
    var layout: [LayoutItem] = []
    var notes: String = ""
}

/// Every scan lives in Documents/Scans/<id>/ (visible in the Files app):
/// scan.json (this record), room.json (raw RoomPlan CapturedRoom), model.usdz, chat.json, photos/.
@Observable
final class ScanStore {
    var records: [ScanRecord] = []

    let root: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let r = docs.appendingPathComponent("Scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: r, withIntermediateDirectories: true)
        return r
    }()

    init() { load() }

    func dir(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    func photoURL(_ rec: ScanRecord, _ p: PhotoRecord) -> URL {
        dir(rec.id).appendingPathComponent("photos").appendingPathComponent(p.fileName)
    }
    func modelURL(_ id: String) -> URL { dir(id).appendingPathComponent("model.usdz") }
    func roomURL(_ id: String) -> URL { dir(id).appendingPathComponent("room.json") }

    func load() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        records = dirs.compactMap { d in
            guard let data = try? Data(contentsOf: d.appendingPathComponent("scan.json")) else { return nil }
            return try? Self.decoder.decode(ScanRecord.self, from: data)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ rec: ScanRecord) {
        let d = dir(rec.id)
        try? FileManager.default.createDirectory(at: d.appendingPathComponent("photos"), withIntermediateDirectories: true)
        if let data = try? Self.encoder.encode(rec) {
            try? data.write(to: d.appendingPathComponent("scan.json"), options: .atomic)
        }
        if let i = records.firstIndex(where: { $0.id == rec.id }) { records[i] = rec }
        else { records.insert(rec, at: 0) }
    }

    func delete(_ rec: ScanRecord) {
        try? FileManager.default.removeItem(at: dir(rec.id))
        records.removeAll { $0.id == rec.id }
    }

    func addPhoto(_ jpeg: Data, to rec: inout ScanRecord, position: P2? = nil, heading: Double? = nil) {
        let id = UUID().uuidString
        let p = PhotoRecord(id: id, fileName: "\(id).jpg", position: position, heading: heading, takenAt: Date())
        let d = dir(rec.id).appendingPathComponent("photos")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? jpeg.write(to: d.appendingPathComponent(p.fileName))
        rec.photos.append(p)
    }

    func image(_ rec: ScanRecord, _ p: PhotoRecord) -> UIImage? { UIImage(contentsOfFile: photoURL(rec, p).path) }

    func loadChat(_ id: String) -> ChatState {
        guard let data = try? Data(contentsOf: dir(id).appendingPathComponent("chat.json")),
              let s = try? Self.decoder.decode(ChatState.self, from: data) else { return ChatState() }
        return s
    }

    func saveChat(_ s: ChatState, _ id: String) {
        if let data = try? Self.encoder.encode(s) { try? data.write(to: dir(id).appendingPathComponent("chat.json")) }
    }

    func nextName() -> String { "Místnost \(records.count + 1)" }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
