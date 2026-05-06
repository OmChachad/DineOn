//
//  NutritionProfileAPIClient.swift
//  DineOn
//
//  Created by Codex on 05/06/26.
//

import Foundation

enum NutritionProfileAPIError: LocalizedError {
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The nutrition server returned an invalid response."
        case .serverError(let message):
            return message
        }
    }
}

final class NutritionProfileAPIClient {
    static let shared = NutritionProfileAPIClient()

    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://dineon-production.up.railway.app/")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func analyze(preferenceNotes: [String], healthkit: HealthKitSnapshot) async throws -> NutritionProfile {
        let requestPayload = NutritionProfileRequestPayload(
            schemaVersion: nutritionProfileSchemaVersion,
            preferenceNotes: preferenceNotes,
            healthkit: healthkit
        )

        var request = URLRequest(url: baseURL.appending(path: "nutrition/profile"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(requestPayload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NutritionProfileAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "<unreadable>"
            print("❌ Nutrition request failed with status \(httpResponse.statusCode): \(responseBody)")
            if let message = try? decoder.decode(ServerErrorResponse.self, from: data).message {
                throw NutritionProfileAPIError.serverError(message)
            }
            throw NutritionProfileAPIError.serverError("Nutrition analysis failed with status \(httpResponse.statusCode).")
        }

        return try decoder.decode(NutritionProfile.self, from: data)
    }

    private var encoder: JSONEncoder {
        JSONEncoder()
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct ServerErrorResponse: Decodable {
    let message: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let detail = try? container.decode(String.self, forKey: .detail) {
            message = detail
            return
        }
        if let details = try? container.decode([ValidationDetail].self, forKey: .detail) {
            message = details.map(\.readableDescription).joined(separator: "\n")
            return
        }
        message = "Nutrition analysis request failed."
    }

    private enum CodingKeys: String, CodingKey {
        case detail
    }
}

private struct ValidationDetail: Decodable {
    let loc: [ValidationLocation]
    let msg: String

    var readableDescription: String {
        let path = loc.map(\.description).joined(separator: ".")
        return path.isEmpty ? msg : "\(path): \(msg)"
    }
}

private enum ValidationLocation: Decodable, CustomStringConvertible {
    case string(String)
    case int(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .int(try container.decode(Int.self))
        }
    }

    var description: String {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        }
    }
}
