//
//  DiningVenue.swift
//  DineOn
//
//  Created by Om Chachad on 03/10/26.
//

import Foundation
import CoreLocation

/// A single source of truth for every USC dining venue's metadata.
enum DiningVenue: String, CaseIterable {
    case village
    case parkside
    case evk
    
    /// The name used by the dining API / data model.
    var apiName: String {
        switch self {
        case .village:  return "USC Village"
        case .parkside: return "Parkside Residential"
        case .evk:      return "Everybody's Kitchen"
        }
    }
    
    /// A compact display name for tabs and UI.
    var shortName: String {
        switch self {
        case .village:  return "Village"
        case .parkside: return "Parkside"
        case .evk:      return "EVK"
        }
    }
    
    /// SF Symbol name for the tab icon.
    var iconName: String {
        switch self {
        case .village:  return "building.columns.fill"
        case .parkside: return "fork.knife"
        case .evk:      return "person.3.fill"
        }
    }
    
    /// GPS coordinates of the venue.
    var coordinate: CLLocation {
        switch self {
        case .village:  return CLLocation(latitude: 34.025889, longitude: -118.286062)
        case .parkside: return CLLocation(latitude: 34.018722, longitude: -118.291131)
        case .evk:      return CLLocation(latitude: 34.021435, longitude: -118.282249)
        }
    }
    
    /// Look up a venue by its API / data-model name.
    static func from(apiName: String) -> DiningVenue? {
        allCases.first { $0.apiName == apiName }
    }
}
