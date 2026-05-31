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
                        metricsGrid(for: state)
                        actionComposer
                        timeline(for: state)
                    }
                    .padding(20)
                    .frame(maxWidth: 1120, alignment: .leading)
                }
                .background(.black.opacity(0.92))
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
        .disabled(store.isAdvancing)
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
