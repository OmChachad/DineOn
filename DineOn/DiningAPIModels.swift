//
//  DiningAPIModels.swift
//  DineOn
//
//  Created by Om Chachad on 10/17/25.
//

import Foundation

// MARK: - USC Hospitality API Response Models

struct DiningAPIResponse: Codable, Sendable {
    let meals: [DiningAPIMeal]?
}

struct DiningAPIMeal: Codable, Sendable {
    let name: String
    let stations: [DiningAPIStation]

    enum CodingKeys: String, CodingKey { case name, stations }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        // Meals not served today omit the stations key entirely
        stations = (try? container.decodeIfPresent([DiningAPIStation].self, forKey: .stations)) ?? []
    }
}

struct DiningAPIStation: Codable, Sendable {
    let station: String
    let subtitle: String?
    let menu: [DiningAPIMenuItem]
}

struct DiningAPIMenuItem: Codable, Sendable {
    let item: String
    let allergens: [String]
    let preferences: [String]
}

/// Free function so it is never actor-isolated, safe to call from `nonisolated` async contexts.
nonisolated func decodeDiningAPIResponse(from data: Data) throws -> DiningAPIResponse {
    try JSONDecoder().decode(DiningAPIResponse.self, from: data)
}
