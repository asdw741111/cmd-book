import Foundation

enum Store {
    static func loadSnapshot() -> Snapshot? {
        AppPaths.prepare()
        guard let data = try? Data(contentsOf: AppPaths.snapshotURL) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func saveSnapshot(_ snapshot: Snapshot) throws {
        AppPaths.prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: AppPaths.snapshotURL, options: [.atomic])
    }

    static func loadSaved() -> SavedStore {
        AppPaths.prepare()
        guard let data = try? Data(contentsOf: AppPaths.savedURL),
              let store = try? JSONDecoder().decode(SavedStore.self, from: data) else {
            return SavedStore()
        }
        return store
    }

    static func saveSaved(_ store: SavedStore) throws {
        AppPaths.prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(store)
        try data.write(to: AppPaths.savedURL, options: [.atomic])
    }
}
