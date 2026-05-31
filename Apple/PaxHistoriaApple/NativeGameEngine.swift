import Foundation

enum NativeGameEngine {
    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func initialState(for country: PlayerCountry) -> NativeCampaignState {
        NativeCampaignState(
            aiReadiness: .notChecked,
            country: country,
            gameDate: "2030-09-15",
            lastSummary: "A campanha começa sem escolher automaticamente outro país. \(country.name) precisa transformar intenção em planos concretos.",
            plannedActions: [],
            round: 1,
            suggestedActions: [],
            stability: 62,
            startDate: "2025-03-25",
            timeline: [
                NativeCampaignEvent(
                    date: "2030-09-15",
                    description: "A campanha começa em uma simulação de planejamento. A primeira decisão importante é escolher prioridades, não reagir a ruído.",
                    id: "opening-\(country.code.lowercased())",
                    importance: .major,
                    kind: .world,
                    linkedActionIDs: [],
                    notable: true,
                    playerRelated: true,
                    strategicEffects: [
                        NativeStrategicEffect(
                            date: "2030-09-15",
                            eventId: "opening-\(country.code.lowercased())",
                            id: "opening-\(country.code.lowercased())-stability",
                            magnitude: 1,
                            summary: "A transição ordenada dá ao jogador um pequeno espaço inicial.",
                            target: country.name,
                            track: .internalStability
                        ),
                    ],
                    title: "\(country.name) abre a mesa de planejamento"
                ),
            ],
            worldTension: 48,
            worldEffects: []
        )
    }

    static func action(from text: String, date: String) -> NativePlannedAction? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let title = trimmed
            .components(separatedBy: CharacterSet(charactersIn: ".\n"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(72) ?? Substring(trimmed.prefix(72))

        return NativePlannedAction(
            createdAt: date,
            detail: trimmed,
            id: "action-\(UUID().uuidString.lowercased())",
            resolvedAt: nil,
            status: .planned,
            title: String(title)
        )
    }

    static func validated(_ turn: NativeGeneratedTurn, state: NativeCampaignState, months: Int) throws -> NativeGeneratedTurn {
        guard !turn.events.isEmpty else {
            throw NativeGameEngineError.invalidTurn("Foundation Models returned no events.")
        }
        guard turn.events.contains(where: { !$0.playerRelated }) else {
            throw NativeGameEngineError.invalidTurn("At least one generated event must be independent of the player country.")
        }
        let summary = turn.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            throw NativeGameEngineError.invalidTurn("Foundation Models returned an empty turn summary.")
        }

        let targetDate = advance(date: state.gameDate, months: months)
        let events = try turn.events.prefix(6).enumerated().map { index, event in
            guard !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) is missing a title.")
            }
            guard !containsFoundationPlaceholderText(event.title) else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) used a schema placeholder instead of a real title.")
            }
            guard !event.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) is missing a description.")
            }
            guard !containsFoundationPlaceholderText(event.description), event.description.split(separator: " ").count >= 8 else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) needs a concrete description.")
            }
            guard !event.strategicEffects.isEmpty else {
                throw NativeGameEngineError.invalidTurn("Event \(event.title) has no strategic effects.")
            }
            guard event.strategicEffects.allSatisfy({ !containsFoundationPlaceholderText($0.summary) && $0.summary.split(separator: " ").count >= 5 }) else {
                throw NativeGameEngineError.invalidTurn("Event \(index + 1) needs a concrete strategic effect summary.")
            }

            return normalized(event, index: index, targetDate: targetDate, country: state.country)
        }

        return NativeGeneratedTurn(
            events: events,
            stabilityDelta: max(-12, min(12, turn.stabilityDelta)),
            summary: summary,
            worldTensionDelta: max(-12, min(12, turn.worldTensionDelta))
        )
    }

    static func apply(
        _ generated: NativeGeneratedTurn,
        to state: NativeCampaignState,
        months: Int
    ) -> NativeCampaignState {
        let targetDate = advance(date: state.gameDate, months: months)
        let generatedEvents = generated.events.enumerated().map { index, event in
            normalized(event, index: index, targetDate: targetDate, country: state.country)
        }
        let linkedActionIDs = Set(generatedEvents.flatMap(\.linkedActionIDs))
        let resolvedActions = state.plannedActions.map { action in
            guard linkedActionIDs.contains(action.id) || action.status == .planned else { return action }
            var next = action
            next.status = .resolved
            next.resolvedAt = targetDate
            return next
        }
        let allEffects = generatedEvents.flatMap(\.strategicEffects)

        return NativeCampaignState(
            aiReadiness: .available(tokenBudget: "guided-generation context=4096, maxResponse=760"),
            country: state.country,
            gameDate: targetDate,
            lastSummary: generated.summary,
            plannedActions: resolvedActions,
            round: state.round + 1,
            suggestedActions: [],
            stability: clamp(state.stability + generated.stabilityDelta + allEffects.filter { $0.track == .internalStability }.map(\.magnitude).reduce(0, +)),
            startDate: state.startDate,
            timeline: (generatedEvents + state.timeline).prefix(80).map { $0 },
            worldTension: clamp(state.worldTension + generated.worldTensionDelta + allEffects.filter { $0.track == .worldTension || $0.track == .securityAnxiety }.map(\.magnitude).reduce(0, +)),
            worldEffects: (allEffects + state.worldEffects).prefix(160).map { $0 }
        )
    }

    static func advance(date: String, months: Int) -> String {
        guard let value = displayFormatter.date(from: date) else { return date }
        let next = Calendar(identifier: .gregorian).date(byAdding: .month, value: months, to: value) ?? value
        return displayFormatter.string(from: next)
    }

    static func todayStamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func normalized(_ event: NativeCampaignEvent, index: Int, targetDate: String, country: PlayerCountry) -> NativeCampaignEvent {
        var next = event
        if next.id.isEmpty {
            next.id = "generated-\(targetDate)-\(index)"
        }
        if next.date.isEmpty {
            next.date = targetDate
        }
        if next.title.isEmpty {
            next.title = next.playerRelated ? "\(country.name) enfrenta novo ponto de decisão" : "O sistema internacional se move"
        }
        next.strategicEffects = next.strategicEffects.enumerated().map { effectIndex, effect in
            var nextEffect = effect
            if nextEffect.id.isEmpty {
                nextEffect.id = "\(next.id)-effect-\(effectIndex)"
            }
            if nextEffect.eventId.isEmpty {
                nextEffect.eventId = next.id
            }
            if nextEffect.date.isEmpty {
                nextEffect.date = next.date
            }
            if nextEffect.target.isEmpty {
                nextEffect.target = next.playerRelated ? country.name : "International system"
            }
            nextEffect.magnitude = max(-5, min(5, nextEffect.magnitude))
            return nextEffect
        }
        return next
    }

    private static func clamp(_ value: Int) -> Int {
        max(0, min(100, value))
    }

}
