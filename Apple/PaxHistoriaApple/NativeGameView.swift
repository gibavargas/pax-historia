import MapKit
import SwiftUI

struct NativeGameView: View {
    @ObservedObject var store: NativeCampaignStore

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let state = store.state {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(for: state)
                        NativeWorldMap(state: state)
                        metricsGrid(for: state)
                        if let error = store.lastError, !error.isEmpty {
                            ErrorBanner(message: error)
                        }
                        actionComposer
                        timeline(for: state)
                    }
                    .padding(20)
                    .frame(maxWidth: 1120, alignment: .leading)
                }
                .background(.black.opacity(0.92))
                .task(id: "\(state.country.code)-\(state.round)") {
                    await store.refreshSuggestedActionsIfNeeded()
                }
            } else {
                ContentUnavailableView("No campaign loaded", systemImage: "globe", description: Text("Choose a country to begin."))
            }
        }
        .background(.black)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let state = store.state {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.country.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("\(state.country.code) · Round \(state.round)")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label(state.gameDate, systemImage: "calendar")
                    Label("Stability \(state.stability)", systemImage: "building.columns")
                    Label("World tension \(state.worldTension)", systemImage: "waveform.path.ecg")
                }
                .font(.callout)

                Divider()

                aiStatus(state.aiReadiness)

                Button {
                    Task { await store.checkAppleStatus() }
                } label: {
                    Label("Check Apple status", systemImage: "cpu")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("native-apple-status-check")

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Advance")
                        .font(.headline)
                    HStack {
                        advanceButton(months: 1, title: "1 month")
                        advanceButton(months: 3, title: "3 months")
                    }
                    advanceButton(months: 12, title: "1 year")
                }

                Button {
                    Task { await store.refreshSuggestedActions(force: true) }
                } label: {
                    Label("Suggest actions", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .disabled(store.isLoadingSuggestions)

                Spacer()

                Button(role: .destructive) {
                    store.resetSelection()
                } label: {
                    Label("Change country", systemImage: "flag")
                }
                .accessibilityIdentifier("native-change-country")
            }
        }
        .padding()
        .navigationTitle("Pax Historia")
    }

    private func header(for state: NativeCampaignState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Native Strategy Room")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(2)

            Text(state.lastSummary)
                .font(.title2)
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metricsGrid(for state: NativeCampaignState) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
            MetricCard(title: "Planned Actions", value: "\(state.plannedActions.filter { $0.status == .planned }.count)", systemImage: "checklist")
            MetricCard(title: "Strategic Effects", value: "\(state.worldEffects.count)", systemImage: "chart.line.uptrend.xyaxis")
            MetricCard(title: "Independent Events", value: "\(state.timeline.filter { !$0.playerRelated }.count)", systemImage: "globe.europe.africa")
            MetricCard(title: "AI Status", value: formatAvailability(state.aiReadiness.availability), systemImage: "brain")
        }
    }

    private var actionComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Orders")
                .font(.headline)
            Text("Write concrete instruments, not vague wishes. The next time jump turns them into consequences.")
                .font(.callout)
                .foregroundStyle(.secondary)

            suggestedActions

            TextEditor(text: $store.draftAction)
                .frame(minHeight: 88)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityIdentifier("native-action-editor")

            HStack {
                Button {
                    store.addDraftAction()
                } label: {
                    Label("Add order", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.draftAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }

            if let state = store.state, !state.plannedActions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(state.plannedActions.prefix(5)) { action in
                        ActionRow(action: action)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var suggestedActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Apple-suggested actions", systemImage: "sparkles")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if store.isLoadingSuggestions {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await store.refreshSuggestedActions(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Refresh Apple-suggested actions")
                }
            }

            if let suggestionError = store.lastSuggestionError, !suggestionError.isEmpty {
                SuggestionWarning(message: suggestionError)
            }

            if let state = store.state, !state.suggestedActions.isEmpty {
                ForEach(state.suggestedActions) { suggestion in
                    SuggestedActionRow(suggestion: suggestion) {
                        store.addSuggestedAction(suggestion)
                    }
                }
            } else if store.isLoadingSuggestions {
                Text("Asking Apple Foundation Models for concrete orders...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No suggestions yet. Use refresh to ask Apple Foundation Models.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func timeline(for state: NativeCampaignState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Events")
                .font(.headline)

            ForEach(state.timeline) { event in
                EventCard(event: event)
            }
        }
    }

    private func advanceButton(months: Int, title: String) -> some View {
        Button {
            Task { await store.advance(months: months) }
        } label: {
            if store.isAdvancing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(title)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.isAdvancing || store.isLoadingSuggestions)
        .accessibilityIdentifier("native-advance-\(months)")
    }

    private func aiStatus(_ readiness: NativeAIReadiness) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(formatAvailability(readiness.availability), systemImage: readiness.availability == "available" ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.headline)
            if readiness.checkedAt.isEmpty {
                Text("Not checked yet")
                    .foregroundStyle(.secondary)
            } else {
                Text("Checked \(readiness.checkedAt)")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !readiness.recoverySuggestion.isEmpty {
                Text(readiness.recoverySuggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
    }

    private func formatAvailability(_ value: String) -> String {
        switch value {
        case "apple-intelligence-not-enabled": return "Apple Intelligence off"
        case "available": return "Apple FM ready"
        case "model-not-ready": return "Model not ready"
        case "not-checked": return "Not checked"
        case "unsupported-os": return "Unsupported OS"
        default: return value.isEmpty ? "Unknown" : value
        }
    }
}

private struct NativeWorldMap: View {
    let state: NativeCampaignState

    private let coordinate: CLLocationCoordinate2D
    private let region: MKCoordinateRegion

    init(state: NativeCampaignState) {
        self.state = state
        coordinate = CountryCoordinate.center(for: state.country.code)
        let span = state.country.code == "ATA"
            ? MKCoordinateSpan(latitudeDelta: 80, longitudeDelta: 160)
            : MKCoordinateSpan(latitudeDelta: 34, longitudeDelta: 48)
        region = MKCoordinateRegion(center: coordinate, span: span)
    }

    var body: some View {
        Map(initialPosition: .region(region)) {
            Marker(state.country.name, systemImage: "flag.fill", coordinate: coordinate)
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(minHeight: 300)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Strategic Map")
                    .font(.caption)
                    .fontWeight(.bold)
                    .textCase(.uppercase)
                    .tracking(1.6)
                Text("\(state.country.name) focus · \(state.worldTension)/100 world tension")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(12)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityIdentifier("native-strategic-map")
    }
}

private enum CountryCoordinate {
    static func center(for code: String) -> CLLocationCoordinate2D {
        let pair = centroids[code.uppercased()] ?? (20.0, 0.0)
        return CLLocationCoordinate2D(latitude: pair.0, longitude: pair.1)
    }

    private static let centroids: [String: (Double, Double)] = [
        "ARG": (-38.4, -63.6),
        "AUS": (-25.3, 133.8),
        "BRA": (-10.3, -53.2),
        "CAN": (56.1, -106.3),
        "CHN": (35.9, 104.2),
        "DEU": (51.2, 10.4),
        "EGY": (26.8, 30.8),
        "ESP": (40.5, -3.7),
        "FRA": (46.2, 2.2),
        "GBR": (55.4, -3.4),
        "IND": (20.6, 78.9),
        "IDN": (-2.5, 118.0),
        "IRN": (32.4, 53.7),
        "ITA": (41.9, 12.6),
        "JPN": (36.2, 138.3),
        "KOR": (36.5, 127.9),
        "MEX": (23.6, -102.5),
        "NGA": (9.1, 8.7),
        "RUS": (61.5, 105.3),
        "SAU": (23.9, 45.1),
        "TUR": (39.0, 35.2),
        "UKR": (48.4, 31.2),
        "USA": (39.8, -98.6),
        "ZAF": (-30.6, 22.9),
    ]
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityIdentifier("native-apple-error")
    }
}

private struct SuggestionWarning: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityIdentifier("native-apple-suggestion-warning")
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SuggestedActionRow: View {
    let suggestion: NativeSuggestedAction
    let onUse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title)
                        .fontWeight(.semibold)
                    Text(suggestion.urgency.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onUse()
                } label: {
                    Label("Use", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
            }

            Text(suggestion.detail)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            Text(suggestion.rationale)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ActionRow: View {
    let action: NativePlannedAction

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: action.status == .resolved ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(action.status == .resolved ? .green : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .fontWeight(.semibold)
                Text(action.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EventCard: View {
    let event: NativeCampaignEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.headline)
                    Text("\(event.date) · \(event.kind.rawValue) · \(event.importance.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(event.playerRelated ? "Player" : "World")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(event.playerRelated ? .blue.opacity(0.22) : .purple.opacity(0.22), in: Capsule())
            }

            Text(event.description)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !event.strategicEffects.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(event.strategicEffects) { effect in
                        HStack(alignment: .top, spacing: 8) {
                            Text(effect.magnitude > 0 ? "+\(effect.magnitude)" : "\(effect.magnitude)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(effect.magnitude >= 0 ? .green : .red)
                                .frame(width: 34, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(effect.track.rawValue)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(effect.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
