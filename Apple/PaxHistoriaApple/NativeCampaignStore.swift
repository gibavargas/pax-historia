import Foundation

@MainActor
final class NativeCampaignStore: ObservableObject {
    @Published private(set) var selectedCountry: PlayerCountry?
    @Published private(set) var state: NativeCampaignState?
    @Published var draftAction = ""
    @Published private(set) var isAdvancing = false
    @Published private(set) var isLoadingSuggestions = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSuggestionError: String?

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let aiService: NativeFoundationModelService

    private static let selectedCountryKey = "pax-historia.native.selected-country.v1"
    private static let campaignStateKey = "pax-historia.native.campaign-state.v1"

    init(defaults: UserDefaults = .standard, aiService: NativeFoundationModelService = NativeFoundationModelService()) {
        let decoder = JSONDecoder()
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = decoder
        self.aiService = aiService
        selectedCountry = Self.loadSelectedCountry(from: defaults, decoder: decoder)
        state = Self.loadCampaignState(from: defaults, decoder: decoder)
            .map(Self.normalizedLoadedState)

        if let selectedCountry, state == nil {
            state = NativeGameEngine.initialState(for: selectedCountry)
            persistState()
        }
    }

    func choose(_ country: PlayerCountry) {
        selectedCountry = country
        state = NativeGameEngine.initialState(for: country)
        lastError = nil
        lastSuggestionError = nil
        if let data = try? encoder.encode(country) {
            defaults.set(data, forKey: Self.selectedCountryKey)
        }
        persistState()
        Task { await refreshSuggestedActions(force: true) }
    }

    func resetSelection() {
        selectedCountry = nil
        state = nil
        draftAction = ""
        lastError = nil
        lastSuggestionError = nil
        defaults.removeObject(forKey: Self.selectedCountryKey)
        defaults.removeObject(forKey: Self.campaignStateKey)
    }

    func addDraftAction() {
        guard var state else { return }
        let action = NativeGameEngine.action(from: draftAction, date: state.gameDate)
        guard let action else { return }

        state.plannedActions.insert(action, at: 0)
        state.lastSummary = "\(action.title) foi colocado na mesa do gabinete. O efeito real virá no próximo salto temporal."
        self.state = state
        draftAction = ""
        persistState()
    }

    func addSuggestedAction(_ suggestion: NativeSuggestedAction) {
        guard var state else { return }
        let detail = suggestion.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else { return }

        let action = NativePlannedAction(
            createdAt: state.gameDate,
            detail: detail,
            id: "action-\(UUID().uuidString.lowercased())",
            resolvedAt: nil,
            status: .planned,
            title: suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        state.plannedActions.insert(action, at: 0)
        state.suggestedActions.removeAll { $0.id == suggestion.id }
        state.lastSummary = "\(action.title) foi aceito como ordem planejada. O Apple Foundation Model resolverá seu impacto no próximo salto temporal."
        self.state = state
        persistState()
    }

    func deleteActions(at offsets: IndexSet) {
        guard var state else { return }
        for index in offsets.sorted(by: >) where state.plannedActions.indices.contains(index) {
            state.plannedActions.remove(at: index)
        }
        self.state = state
        persistState()
    }

    func checkAppleStatus() async {
        guard var state else { return }
        state.aiReadiness = await aiService.checkReadiness()
        self.state = state
        persistState()
    }

    func advance(months: Int) async {
        guard var currentState = state, !isAdvancing else { return }

        isAdvancing = true
        lastError = nil
        defer { isAdvancing = false }

        do {
            let generated = try await aiService.generateTurn(for: currentState, months: months)
            currentState = NativeGameEngine.apply(
                generated,
                to: currentState,
                months: months
            )

            state = currentState
            lastError = nil
            persistState()
            await refreshSuggestedActions(force: true)
        } catch {
            currentState.aiReadiness = .failure(error)
            state = currentState
            lastError = error.localizedDescription
            persistState()
        }
    }

    func refreshSuggestedActionsIfNeeded() async {
        guard let state, state.suggestedActions.isEmpty else { return }
        await refreshSuggestedActions(force: false)
    }

    func refreshSuggestedActions(force: Bool) async {
        guard var currentState = state, !isLoadingSuggestions else { return }
        guard force || currentState.suggestedActions.isEmpty else { return }

        isLoadingSuggestions = true
        lastSuggestionError = nil
        defer { isLoadingSuggestions = false }

        do {
            let suggestions = try await aiService.generateSuggestedActions(for: currentState)
            currentState.suggestedActions = suggestions
            currentState.aiReadiness = .available(tokenBudget: "sliced-guided-generation context=4096, suggestions=4x180")
            state = currentState
            lastSuggestionError = nil
            persistState()
        } catch {
            state = currentState
            lastSuggestionError = "\(error.localizedDescription) No substitute suggestions were used."
            persistState()
        }
    }

    private func persistState() {
        guard let state, let data = try? encoder.encode(state) else {
            defaults.removeObject(forKey: Self.campaignStateKey)
            return
        }

        defaults.set(data, forKey: Self.campaignStateKey)
    }

    private static func loadSelectedCountry(from defaults: UserDefaults, decoder: JSONDecoder) -> PlayerCountry? {
        guard let data = defaults.data(forKey: selectedCountryKey) else {
            return nil
        }

        return try? decoder.decode(PlayerCountry.self, from: data)
    }

    private static func loadCampaignState(from defaults: UserDefaults, decoder: JSONDecoder) -> NativeCampaignState? {
        guard let data = defaults.data(forKey: campaignStateKey) else {
            return nil
        }

        return try? decoder.decode(NativeCampaignState.self, from: data)
    }

    private static func normalizedLoadedState(_ loaded: NativeCampaignState) -> NativeCampaignState {
        var state = loaded
        if state.aiReadiness.availability == "apple-foundation-error" {
            state.aiReadiness = .notChecked
        }
        state.suggestedActions = []
        state.lastSummary = sanitizeFoundationModelText(state.lastSummary)
        state.plannedActions = state.plannedActions.map { action in
            var action = action
            action.title = sanitizeFoundationModelText(action.title)
            action.detail = sanitizeFoundationModelText(action.detail)
            return action
        }
        state.timeline = state.timeline.compactMap { event in
            var event = event
            event.title = sanitizeFoundationModelText(event.title)
            event.description = sanitizeFoundationModelText(event.description)
            guard !containsFoundationPlaceholderText(event.title), !containsFoundationPlaceholderText(event.description) else {
                return nil
            }
            if event.kind == .crisis {
                event.kind = event.playerRelated ? .action : .world
            }
            event.strategicEffects = event.strategicEffects.compactMap { effect in
                var effect = effect
                effect.summary = sanitizeFoundationModelText(effect.summary)
                effect.target = sanitizeFoundationModelText(effect.target)
                effect.track = foundationVisibleTrack(effect.track)
                guard !containsFoundationPlaceholderText(effect.summary), !containsFoundationPlaceholderText(effect.target) else {
                    return nil
                }
                return effect
            }
            return event
        }
        state.worldEffects = state.worldEffects.compactMap { effect in
            var effect = effect
            effect.summary = sanitizeFoundationModelText(effect.summary)
            effect.target = sanitizeFoundationModelText(effect.target)
            effect.track = foundationVisibleTrack(effect.track)
            guard !containsFoundationPlaceholderText(effect.summary), !containsFoundationPlaceholderText(effect.target) else {
                return nil
            }
            return effect
        }
        return state
    }
}
