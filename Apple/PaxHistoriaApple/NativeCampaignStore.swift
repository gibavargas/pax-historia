import Foundation

@MainActor
final class NativeCampaignStore: ObservableObject {
    @Published private(set) var selectedCountry: PlayerCountry?

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private static let selectedCountryKey = "pax-historia.native.selected-country.v1"

    init(defaults: UserDefaults = .standard) {
        let decoder = JSONDecoder()
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = decoder
        selectedCountry = Self.loadSelectedCountry(from: defaults, decoder: decoder)
    }

    func choose(_ country: PlayerCountry) {
        selectedCountry = country
        if let data = try? encoder.encode(country) {
            defaults.set(data, forKey: Self.selectedCountryKey)
        }
    }

    func resetSelection() {
        selectedCountry = nil
        defaults.removeObject(forKey: Self.selectedCountryKey)
    }

    private static func loadSelectedCountry(from defaults: UserDefaults, decoder: JSONDecoder) -> PlayerCountry? {
        guard let data = defaults.data(forKey: selectedCountryKey) else {
            return nil
        }

        return try? decoder.decode(PlayerCountry.self, from: data)
    }
}
