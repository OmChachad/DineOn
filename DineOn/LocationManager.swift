//
//  LocationManager.swift
//  DineOn
//
//  Created by Om Chachad on 03/10/26.
//

import Foundation
import CoreLocation
import Combine

/// Manages user location and computes distances to USC dining venues.
@MainActor
class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    private let clManager = CLLocationManager()
    
    @Published var userLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    /// Approximate center of the USC campus for the proximity threshold check.
    private static let campusCenter = CLLocation(latitude: 34.0224, longitude: -118.2851)
    
    /// Maximum distance (in meters) from campus center to consider the user "near campus."
    /// ~3 miles covers the broader USC area generously.
    private static let campusRadiusMeters: CLLocationDistance = 4828
    
    // MARK: - Init
    
    private override init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = clManager.authorizationStatus
    }
    
    // MARK: - Public API
    
    func requestLocationPermission() {
        clManager.requestWhenInUseAuthorization()
    }
    
    func requestLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        clManager.requestLocation()
    }
    
    /// Whether the user is close enough to campus for proximity sorting to be meaningful.
    var isNearCampus: Bool {
        guard let location = userLocation else { return false }
        return location.distance(from: Self.campusCenter) <= Self.campusRadiusMeters
    }
    
    /// Returns venue names sorted by distance from the user's current location.
    /// If the user is too far from campus or location is unavailable, returns nil (caller should use default order).
    func sortedVenuesByProximity(_ venueNames: [String]) -> [String]? {
        guard let location = userLocation, isNearCampus else { return nil }
        
        return venueNames.sorted { a, b in
            let distA = distance(to: a, from: location)
            let distB = distance(to: b, from: location)
            return distA < distB
        }
    }
    
    /// Distance in meters from a given location to a named venue. Returns .greatestFiniteMagnitude if unknown.
    private func distance(to venueName: String, from location: CLLocation) -> CLLocationDistance {
        guard let venue = DiningVenue.from(apiName: venueName) else {
            return .greatestFiniteMagnitude
        }
        return location.distance(from: venue.coordinate)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        userLocation = locations.last
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("📍 Location error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            clManager.requestLocation()
        }
    }
}
