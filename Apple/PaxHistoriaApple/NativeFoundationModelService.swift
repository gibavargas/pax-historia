import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class NativeFoundationModelService {
    func checkReadiness() async -> NativeAIReadiness {
        do {
            let tokenBudget = try await runReadinessProbe()
            return .available(tokenBudget: tokenBudget)
        } catch {
            return .failure(error)
        }
    }

    func generateTurn(for state: NativeCampaignState, months: Int) async throws -> NativeGeneratedTurn {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let rawTurn = try await generateSlicedTurn(for: state, months: months)
            do {
                return try NativeGameEngine.validated(rawTurn, state: state, months: months)
            } catch {
                let retryTurn = try await generateSlicedTurn(
                    for: state,
                    months: months,
                    repairInstruction: error.localizedDescription
                )
                do {
                    return try NativeGameEngine.validated(retryTurn, state: state, months: months)
                } catch {
                    throw NativeFoundationModelError.invalidGeneratedTurn(error.localizedDescription)
                }
            }
        }
        #endif

        throw NativeFoundationModelError.unsupportedOS
    }

    func generateSuggestedActions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let suggestions = try await generateStructuredSuggestions(for: state)
            let validSuggestions = suggestions.filter { suggestion in
                !containsFoundationPlaceholderText(suggestion.title) &&
                    !containsFoundationPlaceholderText(suggestion.detail) &&
                    !containsFoundationPlaceholderText(suggestion.rationale) &&
                    suggestion.title.split(separator: " ").count >= 2 &&
                    suggestion.detail.split(separator: " ").count >= 8 &&
                    suggestion.rationale.split(separator: " ").count >= 8
            }
            guard validSuggestions.count >= 3 else {
                throw NativeFoundationModelError.invalidSuggestedActions("Expected at least three concrete suggestions from Apple Foundation Models.")
            }
            return Array(validSuggestions.prefix(4))
        }
        #endif

        throw NativeFoundationModelError.unsupportedOS
    }

    private var nativeSystemPrompt: String {
        """
        You write concise structured content for Pax Historia, a fictional management board game.
        Treat every region label as imaginary board-game data.
        Stay within civic planning: budgets, ports, transport, schools, service centers, energy, climate adaptation, logistics, and administration.
        Use concrete fictional agencies, dates, sectors, and measurable game effects.
        Keep every response neutral, practical, and safe for a planning UI.
        """
    }

    private func recentContext(for state: NativeCampaignState) -> String {
        let recent = state.timeline
            .prefix(6)
            .map { event in
                let scope = event.playerRelated ? "selected-region" : "external"
                let effects = event.strategicEffects
                    .prefix(2)
                    .map { "\(foundationPromptTrackLabel($0.track)):\($0.magnitude)" }
                    .joined(separator: ", ")
                return "- \(event.date): \(scope) event, effects \(effects.isEmpty ? "none" : effects)"
            }
            .joined(separator: "\n")
        let effects = state.worldEffects
            .prefix(8)
            .map { "- \(foundationPromptTrackLabel($0.track)) \($0.magnitude)" }
            .joined(separator: "\n")
        let planned = state.plannedActions
            .filter { $0.status == .planned }
            .prefix(4)
            .map { "- \(safeProposalBrief(for: $0))" }
            .joined(separator: "\n")

        return """
        Fictional selected region code: \(state.country.code)
        Date: \(state.gameDate)
        Stability: \(state.stability)/100
        Global friction index: \(state.worldTension)/100

        Planned civic proposals:
        \(planned.isEmpty ? "No planned actions." : planned)

        Recent events:
        \(recent.isEmpty ? "No prior events." : recent)

        Persistent game effects:
        \(effects.isEmpty ? "No persistent effects yet." : effects)
        """
    }

    private func makeIndependentEventPrompt(for state: NativeCampaignState, months: Int, repairInstruction: String?) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        return """
        Create one external planning development for a Pax Historia board-game turn.
        It must be unrelated to the selected region except through broad economic, logistics, climate, energy, education, or market conditions.
        Use one of these areas: supply flows, climate adaptation, markets, service access, infrastructure, ports, energy, schools, or transit.
        Include one measurable game effect.
        The period starts on \(state.gameDate) and ends on \(targetDate).
        Do not return placeholder labels, Swift type names, schema field names, or generic draft text.
        \(repairInstruction.map { "Repair note: \($0)" } ?? "")

        \(recentContext(for: state))
        """
    }

    private func makeActionEventPrompt(for state: NativeCampaignState, action: NativePlannedAction, months: Int, repairInstruction: String?) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        return """
        Create one player-related civic outcome that resolves or complicates this planned proposal.
        Keep the result at board-game planning level and use only administrative, economic, infrastructure, education, energy, service access, or logistics mechanisms.
        The event must be directly related to the selected region and this action id: \(action.id).
        Planned proposal brief: \(safeProposalBrief(for: action))
        The period starts on \(state.gameDate) and ends on \(targetDate).
        Do not return placeholder labels, Swift type names, schema field names, or generic draft text.
        \(repairInstruction.map { "Repair note: \($0)" } ?? "")

        \(recentContext(for: state))
        """
    }

    private func makeDomesticEventPrompt(for state: NativeCampaignState, months: Int, repairInstruction: String?) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        return """
        Create one selected-region planning event because no planned proposal needs resolution.
        Use administration, budgets, services, infrastructure, education, climate adaptation, energy, or logistics.
        The period starts on \(state.gameDate) and ends on \(targetDate).
        Do not return placeholder labels, Swift type names, schema field names, or generic draft text.
        \(repairInstruction.map { "Repair note: \($0)" } ?? "")

        \(recentContext(for: state))
        """
    }

    private func makeSummaryPrompt(for state: NativeCampaignState, months: Int, events: [NativeCampaignEvent]) -> String {
        let targetDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        let eventLines = events
            .map { event in
                let scope = event.playerRelated ? "selected-region" : "external"
                let effects = event.strategicEffects
                    .prefix(2)
                    .map { "\(foundationPromptTrackLabel($0.track)):\($0.magnitude)" }
                    .joined(separator: ", ")
                return "- \(scope) event, kind=\(event.kind.rawValue), effects=\(effects.isEmpty ? "none" : effects)"
            }
            .joined(separator: "\n")

        return """
        Summarize this Pax Historia period and estimate aggregate deltas.
        Keep it concise, neutral, and focused on fictional board-game planning.
        The period starts on \(state.gameDate) and ends on \(targetDate).
        If you mention a date, use only the exact period dates above.
        Selected region code: \(state.country.code)

        Generated events:
        \(eventLines)
        """
    }

    private func makeSuggestionPrompt(for state: NativeCampaignState, focus: String, index: Int) -> String {
        """
        Create one concrete civic proposal for the next Pax Historia turn.
        Focus area \(index): \(focus).
        The detail must include instrument, target agency or sector, timing, and expected game effect.
        Use only planning areas: logistics, education, infrastructure, energy, climate resilience, fiscal buffers, service access, transport, ports, or industrial capacity.
        Use generic board-game labels for places and agencies.
        Do not claim metric drops, declines, shortages, or failures unless those exact words appear in the recent context.
        Prefer neutral terms like volatility, pressure, capacity gap, or opportunity when interpreting numeric effects.

        \(recentContext(for: state))
        """
    }

    private func safeProposalBrief(for action: NativePlannedAction) -> String {
        let text = "\(action.title) \(action.detail)".lowercased()
        let sector: String
        if text.contains("health") || text.contains("clinic") || text.contains("medical") {
            sector = "community services"
        } else if text.contains("school") || text.contains("education") || text.contains("teacher") {
            sector = "education services"
        } else if text.contains("port") || text.contains("rail") || text.contains("road") || text.contains("transport") || text.contains("logistics") {
            sector = "transport logistics"
        } else if text.contains("energy") || text.contains("grid") {
            sector = "energy systems"
        } else if text.contains("climate") || text.contains("resilience") {
            sector = "climate adaptation"
        } else if text.contains("trade") || text.contains("industry") {
            sector = "trade capacity"
        } else if text.contains("budget") || text.contains("fund") || text.contains("fiscal") {
            sector = "fiscal capacity"
        } else {
            sector = "administrative capacity"
        }

        let instrument: String
        if text.contains("fund") || text.contains("budget") {
            instrument = "budget program"
        } else if text.contains("hub") || text.contains("network") {
            instrument = "coordination hub"
        } else if text.contains("build") || text.contains("construction") || text.contains("upgrade") {
            instrument = "capital project"
        } else if text.contains("hire") || text.contains("training") {
            instrument = "staffing program"
        } else {
            instrument = "planning initiative"
        }

        return "id=\(action.id); sector=\(sector); instrument=\(instrument); timing=next game period"
    }

    private func runReadinessProbe() async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                throw NativeFoundationModelError.modelUnavailable(String(describing: model.availability))
            }

            do {
                let session = LanguageModelSession(
                    model: model,
                    instructions: "You are a one-word readiness probe for Pax Historia."
                )
                let response = try await session.respond(
                    to: "Reply with a short readiness word.",
                    options: GenerationOptions(
                        sampling: .greedy,
                        temperature: 0,
                        maximumResponseTokens: 8
                    )
                )
                guard !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw NativeFoundationModelError.generationFailed("Readiness probe returned empty output.")
                }
                return "guided-generation context=4096, readiness=maxResponse=8"
            } catch let error as NativeFoundationModelError {
                throw error
            } catch {
                throw NativeFoundationModelError.generationFailed(error.localizedDescription)
            }
        }
        #endif

        throw NativeFoundationModelError.unsupportedOS
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
extension NativeFoundationModelService {
    private func generateSlicedTurn(
        for state: NativeCampaignState,
        months: Int,
        repairInstruction: String? = nil
    ) async throws -> NativeGeneratedTurn {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw NativeFoundationModelError.modelUnavailable(String(describing: model.availability))
        }

        var events: [NativeCampaignEvent] = []
        let independentDraft = try await generateEventDraft(
            model: model,
            prompt: makeIndependentEventPrompt(for: state, months: months, repairInstruction: repairInstruction)
        )
        events.append(independentDraft.toNativeEvent(
            state: state,
            months: months,
            index: events.count,
            linkedActionID: nil,
            playerRelated: false
        ))

        let plannedActions = state.plannedActions
            .filter { $0.status == .planned }
            .prefix(3)

        for action in plannedActions {
            let draft = try await generateEventDraft(
                model: model,
                prompt: makeActionEventPrompt(for: state, action: action, months: months, repairInstruction: repairInstruction)
            )
            events.append(draft.toNativeEvent(
                state: state,
                months: months,
                index: events.count,
                linkedActionID: action.id,
                playerRelated: true
            ))
        }

        if events.count < 2 {
            let draft = try await generateEventDraft(
                model: model,
                prompt: makeDomesticEventPrompt(for: state, months: months, repairInstruction: repairInstruction)
            )
            events.append(draft.toNativeEvent(
                state: state,
                months: months,
                index: events.count,
                linkedActionID: nil,
                playerRelated: true
            ))
        }

        let summary = try await generateTurnSummary(model: model, state: state, months: months, events: events)

        return NativeGeneratedTurn(
            events: events,
            stabilityDelta: summary.stabilityDelta,
            summary: sanitizeFoundationModelText(summary.summary),
            worldTensionDelta: summary.globalFrictionDelta
        )
    }

    private func generateEventDraft(
        model: SystemLanguageModel,
        prompt: String
    ) async throws -> AppleNativeGeneratedEventDraft {
        var repairNotes: [String] = []
        for attempt in 1...3 {
            do {
                let session = LanguageModelSession(model: model, instructions: nativeSystemPrompt)
                let response = try await session.respond(
                    to: eventPrompt(prompt, repairNotes: repairNotes),
                    generating: AppleNativeGeneratedEventDraft.self,
                    includeSchemaInPrompt: false,
                    options: GenerationOptions(
                        sampling: .greedy,
                        temperature: attempt == 1 ? 0.08 : 0.12,
                        maximumResponseTokens: 260
                    )
                )
                if response.content.hasConcreteContent {
                    return response.content
                }
                repairNotes.append("Previous event used placeholder or draft text. Produce a concrete title, description, target, and effect summary.")
            } catch {
                if attempt == 3 {
                    throw NativeFoundationModelError.generationFailed(error.localizedDescription)
                }
                repairNotes.append("Previous event generation failed. Try a simpler civic-planning event with one concrete agency and one measurable game effect.")
            }
        }

        throw NativeFoundationModelError.generationFailed("Apple Foundation Models returned placeholder event content after three event-slice attempts.")
    }

    private func eventPrompt(_ basePrompt: String, repairNotes: [String]) -> String {
        guard !repairNotes.isEmpty else { return basePrompt }
        return """
        \(basePrompt)

        Event repair notes:
        \(repairNotes.map { "- \($0)" }.joined(separator: "\n"))
        Banned title words: Apple, Native, Generated, Draft, Placeholder, Schema.
        Use a concrete title like Transit Funding Review, Grid Capacity Program, or School Access Plan.
        """
    }

    private func generateTurnSummary(
        model: SystemLanguageModel,
        state: NativeCampaignState,
        months: Int,
        events: [NativeCampaignEvent]
    ) async throws -> AppleNativeTurnSummary {
        do {
            let session = LanguageModelSession(model: model, instructions: nativeSystemPrompt)
            let response = try await session.respond(
                to: makeSummaryPrompt(for: state, months: months, events: events),
                generating: AppleNativeTurnSummary.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(
                    sampling: .greedy,
                    temperature: 0.05,
                    maximumResponseTokens: 160
                )
            )
            return response.content
        } catch {
            throw NativeFoundationModelError.generationFailed(error.localizedDescription)
        }
    }

    private func generateStructuredSuggestions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw NativeFoundationModelError.modelUnavailable(String(describing: model.availability))
        }

        let focusAreas = [
            "fiscal buffers and community services",
            "trade facilitation and regional logistics",
            "infrastructure, energy, and climate resilience",
            "education, service access, and administrative capacity",
        ]

        var suggestions: [NativeSuggestedAction] = []
        for (index, focus) in focusAreas.enumerated() {
            let basePrompt = makeSuggestionPrompt(for: state, focus: focus, index: index + 1)
            var repairNotes: [String] = []
            var acceptedSuggestion: NativeSuggestedAction?

            for attempt in 1...2 {
                do {
                    let session = LanguageModelSession(model: model, instructions: nativeSystemPrompt)
                    let response = try await session.respond(
                        to: suggestionPrompt(basePrompt, repairNotes: repairNotes),
                        generating: AppleNativeSuggestedAction.self,
                        includeSchemaInPrompt: true,
                        options: GenerationOptions(
                            sampling: .greedy,
                            temperature: attempt == 1 ? 0.08 : 0.12,
                            maximumResponseTokens: 180
                        )
                    )

                    if response.content.hasConcreteContent {
                        acceptedSuggestion = response.content.toNativeSuggestion(state: state, index: index)
                        break
                    }
                    repairNotes.append("Previous proposal was too vague, used placeholder text, or contradicted current metrics. Produce a concrete neutral proposal.")
                } catch let error as NativeFoundationModelError {
                    throw error
                } catch {
                    if attempt == 2 {
                        throw NativeFoundationModelError.generationFailed(error.localizedDescription)
                    }
                    repairNotes.append("Previous proposal generation failed. Try a shorter neutral civic-planning proposal.")
                }
            }

            guard let acceptedSuggestion else {
                throw NativeFoundationModelError.invalidSuggestedActions("Apple Foundation Models returned an invalid suggestion for focus area \(index + 1).")
            }
            suggestions.append(acceptedSuggestion)
        }

        return suggestions
    }

    private func suggestionPrompt(_ basePrompt: String, repairNotes: [String]) -> String {
        guard !repairNotes.isEmpty else { return basePrompt }
        return """
        \(basePrompt)

        Suggestion repair notes:
        \(repairNotes.map { "- \($0)" }.joined(separator: "\n"))
        Banned title words: Apple, Native, Generated, Draft, Placeholder, Schema.
        """
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct AppleNativeGeneratedEventDraft {
    @Guide(description: "Specific civic-planning event title with generic fictional agencies. Never use a schema type name or placeholder title.")
    var title: String

    @Guide(description: "A concrete high-level description with generic agencies, sectors, and game consequences. Never use placeholder or draft text.")
    var description: String

    @Guide(description: "One of: action, economy, world.")
    var kind: String

    @Guide(description: "One of: minor, major.")
    var importance: String

    @Guide(description: "True when the event deserves timeline attention.")
    var notable: Bool

    @Guide(description: "The target region, agency, sector, or external system.")
    var effectTarget: String

    @Guide(description: "One of: economic-resilience, internal-stability, market-confidence.")
    var effectTrack: String

    @Guide(description: "A number from -5 to 5.")
    var effectMagnitude: Int

    @Guide(description: "One concrete sentence explaining the mechanical consequence. Never use placeholder or draft text.")
    var effectSummary: String

    var hasConcreteContent: Bool {
        !containsFoundationPlaceholderText(title) &&
            !containsFoundationPlaceholderText(description) &&
            !containsFoundationPlaceholderText(effectSummary) &&
            description.split(separator: " ").count >= 8 &&
            effectSummary.split(separator: " ").count >= 5
    }

    func toNativeEvent(
        state: NativeCampaignState,
        months: Int,
        index: Int,
        linkedActionID: String?,
        playerRelated: Bool
    ) -> NativeCampaignEvent {
        let eventDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        let eventID = "apple-event-\(state.round)-\(index)-\(UUID().uuidString.prefix(6).lowercased())"
        let target = effectTarget.isEmpty
            ? (playerRelated ? state.country.name : "International system")
            : effectTarget
        let generatedKind = NativeEventKind(rawValue: kind) ?? (playerRelated ? .action : .world)
        let safeKind: NativeEventKind = generatedKind == .crisis ? (playerRelated ? .action : .world) : generatedKind

        return NativeCampaignEvent(
            date: eventDate,
            description: sanitizeFoundationModelText(description),
            id: eventID,
            importance: NativeEventImportance(rawValue: importance) ?? .major,
            kind: safeKind,
            linkedActionIDs: linkedActionID.map { [$0] } ?? [],
            notable: notable,
            playerRelated: playerRelated,
            strategicEffects: [
                NativeStrategicEffect(
                    date: eventDate,
                    eventId: eventID,
                    id: "\(eventID)-effect",
                    magnitude: max(-5, min(5, effectMagnitude)),
                    summary: sanitizeFoundationModelText(effectSummary),
                    target: sanitizeFoundationModelText(target),
                    track: NativeStrategicTrack(rawValue: effectTrack) ?? .marketConfidence
                ),
            ],
            title: sanitizeFoundationModelText(title)
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct AppleNativeTurnSummary {
    @Guide(description: "One concise sentence summarizing why the generated period matters.")
    var summary: String

    @Guide(description: "A number from -12 to 12 indicating domestic stability change.")
    var stabilityDelta: Int

    @Guide(description: "A number from -12 to 12 indicating global friction index change.")
    var globalFrictionDelta: Int
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct AppleNativeSuggestedAction {
    @Guide(description: "Short imperative title for the civic proposal.")
    var title: String

    @Guide(description: "Concrete board-game planning proposal with instrument, generic agency or sector, timing, and intended game effect.")
    var detail: String

    @Guide(description: "Why this civic proposal fits the current campaign state.")
    var rationale: String

    @Guide(description: "One of: immediate, soon, opportunistic.")
    var urgency: String

    var hasConcreteContent: Bool {
        let safeTitle = sanitizeFoundationModelText(title)
        let safeDetail = sanitizeFoundationModelText(detail)
        let safeRationale = sanitizeFoundationModelText(rationale)
        return !containsFoundationPlaceholderText(safeTitle) &&
            !containsFoundationPlaceholderText(safeDetail) &&
            !containsFoundationPlaceholderText(safeRationale) &&
            safeTitle.split(separator: " ").count >= 2 &&
            safeDetail.split(separator: " ").count >= 8 &&
            safeRationale.split(separator: " ").count >= 8
    }

    func toNativeSuggestion(state: NativeCampaignState, index: Int) -> NativeSuggestedAction {
        NativeSuggestedAction(
            detail: sanitizeFoundationModelText(detail),
            id: "suggestion-\(state.country.code.lowercased())-\(state.round)-\(index)",
            rationale: sanitizeFoundationModelText(rationale),
            title: sanitizeFoundationModelText(title),
            urgency: urgency
        )
    }
}

#endif
