import SwiftUI

struct ContentView: View {
    @StateObject private var campaignStore = NativeCampaignStore()

    var body: some View {
        Group {
            if let selectedCountry = campaignStore.selectedCountry {
                NativeGameContainer(
                    selectedCountry: selectedCountry,
                    onChangeCountry: campaignStore.resetSelection
                )
            } else {
                CountrySelectionView(
                    countries: CountryCatalog.all,
                    onSelect: campaignStore.choose
                )
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}

private struct NativeGameContainer: View {
    let selectedCountry: PlayerCountry
    let onChangeCountry: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NativeWebGameView(selectedCountry: selectedCountry)
                .ignoresSafeArea()

            Button {
                onChangeCountry()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "flag.fill")
                    Text(selectedCountry.name)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .font(.callout)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding()
            .accessibilityIdentifier("native-change-country")
        }
        .background(Color.black)
    }
}
