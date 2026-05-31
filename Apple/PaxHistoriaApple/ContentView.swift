import SwiftUI

struct ContentView: View {
    @StateObject private var campaignStore = NativeCampaignStore()

    var body: some View {
        Group {
            if campaignStore.selectedCountry != nil {
                NativeGameView(store: campaignStore)
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
