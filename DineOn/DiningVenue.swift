//
//  DiningVenue.swift
//  DineOn
//
//  Created by Om Chachad on 03/10/26.
//

import Foundation
import CoreLocation

/// Centralised model for every known USC dining venue.
/// Maps the raw API name to a short display name, SF Symbol, and GPS coordinate.
enum DiningVenue: String, CaseIterable {
    case village   = "USC Village"
    case parkside  = "Parkside Residential"
    case evk       = "Everybody's Kitchen"

    /// The slug used by the USC Hospitality API (`get-res-dining-menus/{apiID}`).
    nonisolated var apiID: String {
        switch self {
        case .village:  return "university-village"
        case .parkside: return "parkside"
        case .evk:      return "evk"
        }
    }

    /// Short, user-facing label shown in the tab bar.
    var shortName: String {
        switch self {
        case .village:  return "Village"
        case .parkside: return "Parkside"
        case .evk:      return "EVK"
        }
    }

    /// SF Symbol used for the tab icon.
    var iconName: String {
        switch self {
        case .village:  return "building.columns.fill"
        case .parkside: return "fork.knife"
        case .evk:      return "person.3.fill"
        }
    }

    /// GPS location of the venue.
    var location: CLLocation {
        switch self {
        case .village:  return CLLocation(latitude: 34.025889, longitude: -118.286062)
        case .parkside: return CLLocation(latitude: 34.018722, longitude: -118.291131)
        case .evk:      return CLLocation(latitude: 34.021435, longitude: -118.282249)
        }
    }

    /// EasyCode feedback form for the venue.
    var feedbackURL: URL {
        switch self {
        case .village:
            return URL(string: "https://easycode.com/uscvillage")!
        case .parkside:
            return URL(string: "https://easycode.com/uscparkside")!
        case .evk:
            return URL(string: "https://easycode.com/evk")!
        }
    }
}
