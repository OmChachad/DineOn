//
//  NutritionProfileFileStore.swift
//  DineOn
//
//  Created by Codex on 05/06/26.
//

import Foundation

actor NutritionProfileFileStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> NutritionProfileStoredSnapshot {
        let fileURL = try snapshotURL()
        guard fileManager.fileExists(atPath: fileURL.path()) else {
            return NutritionProfileStoredSnapshot()
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(NutritionProfileStoredSnapshot.self, from: data)
    }

    func save(_ snapshot: NutritionProfileStoredSnapshot) throws {
        let directoryURL = try storageDirectoryURL()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileURL = directoryURL.appendingPathComponent("nutrition-profile.json")
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    private func storageDirectoryURL() throws -> URL {
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return baseURL.appendingPathComponent("DineOn", isDirectory: true)
    }

    private func snapshotURL() throws -> URL {
        try storageDirectoryURL().appendingPathComponent("nutrition-profile.json")
    }
}
