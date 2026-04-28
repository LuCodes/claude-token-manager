import Foundation

/// Coefficients used to translate token volume into a coarse environmental
/// footprint and a few intuitive equivalences. The numbers are best-effort
/// industry averages — see docs/ENVIRONMENTAL_IMPACT.md for sources.
public enum EnvironmentalConstants {

    // Per million tokens.
    public static let kWhPerMillionTokens: Double = 1.0     // ~1 kWh / 1M tokens (Patterson 2021 ballpark)
    public static let litersWaterPerMillion: Double = 500.0 // datacenter cooling
    public static let gCO2PerMillion: Double = 300.0        // US grid-mix average

    // Equivalences.
    public static let gCO2PerCarKm: Double = 120.0           // average gasoline car
    public static let kWhPerGoogleSearch: Double = 0.0003   // ~0.3 Wh per query
    public static let kWhPerNetflixHour: Double = 0.8        // ~0.8 kWh / streaming hour

    public static func compute(millionTokens m: Double) -> EnvironmentalImpact {
        let energy = m * kWhPerMillionTokens
        let water  = m * litersWaterPerMillion
        let co2    = m * gCO2PerMillion
        return EnvironmentalImpact(
            energyKWh:      energy,
            waterLiters:    water,
            co2Grams:       co2,
            carKm:          co2 / gCO2PerCarKm,
            googleSearches: Int((energy / kWhPerGoogleSearch).rounded()),
            netflixHours:   energy / kWhPerNetflixHour
        )
    }
}

public struct EnvironmentalImpact: Sendable, Equatable {
    public let energyKWh:      Double
    public let waterLiters:    Double
    public let co2Grams:       Double
    public let carKm:          Double
    public let googleSearches: Int
    public let netflixHours:   Double
}
