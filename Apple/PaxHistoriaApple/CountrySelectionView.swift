import SwiftUI

struct CountrySelectionView: View {
    let countries: [PlayerCountry]
    let onSelect: (PlayerCountry) -> Void

    @State private var query = ""

    private var filteredCountries: [PlayerCountry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return countries
        }

        return countries.filter { country in
            country.name.localizedCaseInsensitiveContains(normalizedQuery) ||
                country.code.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.018, blue: 0.015),
                    Color(red: 0.08, green: 0.06, blue: 0.035),
                    Color.black,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                header

                TextField("Search country or ISO code", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("native-country-search")

                List(filteredCountries) { country in
                    Button {
                        onSelect(country)
                    } label: {
                        CountryRow(country: country)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("native-country-option-\(country.code)")
                }
                .listStyle(.plain)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    if filteredCountries.isEmpty {
                        Text("No country matched that search.")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
            }
            .frame(maxWidth: 760, maxHeight: 720)
            .padding(24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pax Historia")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(2.6)

            Text("Choose your country")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Text("The campaign will not begin until you explicitly choose who you are playing.")
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("native-country-selection")
    }
}

private struct CountryRow: View {
    let country: PlayerCountry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(country.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Text(country.code)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
    }
}
