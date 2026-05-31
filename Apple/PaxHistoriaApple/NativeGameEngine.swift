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
            lastSummary: "A campanha começa sem escolher automaticamente outro país. \(country.name) precisa transformar intenção em instrumentos concretos.",
            plannedActions: [],
            round: 1,
            stability: 62,
            startDate: "2025-03-25",
            timeline: [
                NativeCampaignEvent(
                    date: "2030-09-15",
                    description: "O gabinete assume a simulação em um mundo divergente. A primeira decisão importante é escolher prioridades, não reagir a ruído.",
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
                            summary: "A transição ordenada dá ao jogador um pequeno espaço político inicial.",
                            target: country.name,
                            track: .internalStability
                        ),
                    ],
                    title: "\(country.name) abre a mesa estratégica"
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

    static func generatedTurn(from rawText: String, fallbackState state: NativeCampaignState, months: Int) -> NativeGeneratedTurn {
        if let generated = decodeGeneratedTurn(rawText), !generated.events.isEmpty {
            return sanitize(generated, fallbackState: state, months: months)
        }

        return fallbackTurn(for: state, months: months)
    }

    static func apply(
        _ generated: NativeGeneratedTurn,
        to state: NativeCampaignState,
        months: Int,
        aiResponse: AppleAIResponse
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
            aiReadiness: NativeAIReadiness(response: aiResponse),
            country: state.country,
            gameDate: targetDate,
            lastSummary: generated.summary,
            plannedActions: resolvedActions,
            round: state.round + 1,
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

    private static func decodeGeneratedTurn(_ rawText: String) -> NativeGeneratedTurn? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidates = [
            trimmed,
            extractJSONBlock(from: trimmed),
            extractJSONObject(from: trimmed),
        ].compactMap { $0 }

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let turn = try? JSONDecoder().decode(NativeGeneratedTurn.self, from: data) {
                return turn
            }
        }

        return nil
    }

    private static func extractJSONBlock(from text: String) -> String? {
        guard let range = text.range(of: "```") else { return nil }
        let remainder = text[range.upperBound...]
        guard let end = remainder.range(of: "```") else { return nil }
        return remainder[..<end.lowerBound]
            .replacingOccurrences(of: "json", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        return String(text[start...end])
    }

    private static func sanitize(_ turn: NativeGeneratedTurn, fallbackState state: NativeCampaignState, months: Int) -> NativeGeneratedTurn {
        var events = turn.events
        if !events.contains(where: { !$0.playerRelated }) {
            events.append(independentWorldEvent(for: state, date: advance(date: state.gameDate, months: months), index: events.count))
        }

        return NativeGeneratedTurn(
            events: events.prefix(6).map { $0 },
            stabilityDelta: max(-12, min(12, turn.stabilityDelta)),
            summary: turn.summary.isEmpty ? "O período altera incentivos, custos e riscos concretos." : turn.summary,
            worldTensionDelta: max(-12, min(12, turn.worldTensionDelta))
        )
    }

    private static func fallbackTurn(for state: NativeCampaignState, months: Int) -> NativeGeneratedTurn {
        let targetDate = advance(date: state.gameDate, months: months)
        var events: [NativeCampaignEvent] = state.plannedActions
            .filter { $0.status == .planned }
            .prefix(3)
            .enumerated()
            .map { index, action in
                actionEvent(for: action, state: state, date: targetDate, index: index)
            }

        events.append(independentWorldEvent(for: state, date: targetDate, index: events.count))

        if events.count < 2 {
            events.append(secondOrderEvent(for: state, date: targetDate, index: events.count))
        }

        let summary = events
            .prefix(2)
            .map(\.title)
            .joined(separator: "; ")

        return NativeGeneratedTurn(
            events: events,
            stabilityDelta: events.reduce(0) { $0 + $1.strategicEffects.filter { $0.track == .internalStability }.map(\.magnitude).reduce(0, +) },
            summary: summary.isEmpty ? "O mundo se move em torno de riscos reais, não apenas em torno do jogador." : summary,
            worldTensionDelta: events.reduce(0) { $0 + $1.strategicEffects.filter { $0.track == .worldTension || $0.track == .securityAnxiety }.map(\.magnitude).reduce(0, +) }
        )
    }

    private static func actionEvent(for action: NativePlannedAction, state: NativeCampaignState, date: String, index: Int) -> NativeCampaignEvent {
        let profile = classify(action.detail)
        let eventId = "event-\(date)-\(action.id.suffix(8))"
        let pressure = state.worldTension >= 65 ? "em ambiente de tensão elevada" : "com margem diplomática ainda administrável"

        return NativeCampaignEvent(
            date: date,
            description: "\(state.country.name) executa: \(action.detail). O movimento deixa de ser intenção e vira custo político: burocracias precisam responder, rivais atualizam leitura de risco e aliados passam a cobrar sinais de continuidade. Isso ocorre \(pressure), então os efeitos não são automáticos nem gratuitos.",
            id: eventId,
            importance: profile.importance,
            kind: profile.kind,
            linkedActionIDs: [action.id],
            notable: true,
            playerRelated: true,
            strategicEffects: [
                NativeStrategicEffect(
                    date: date,
                    eventId: eventId,
                    id: "\(eventId)-primary",
                    magnitude: profile.primaryMagnitude,
                    summary: profile.primarySummary,
                    target: state.country.name,
                    track: profile.primaryTrack
                ),
                NativeStrategicEffect(
                    date: date,
                    eventId: eventId,
                    id: "\(eventId)-friction",
                    magnitude: profile.frictionMagnitude,
                    summary: profile.frictionSummary,
                    target: state.country.name,
                    track: profile.frictionTrack
                ),
            ],
            title: "\(state.country.name) transforma \(action.title.lowercased()) em política executada"
        )
    }

    private static func independentWorldEvent(for state: NativeCampaignState, date: String, index: Int) -> NativeCampaignEvent {
        let templates: [(String, String, NativeEventKind, NativeStrategicTrack, Int)] = [
            (
                "Corredores de energia redesenham barganhas regionais",
                "Produtores, seguradoras e autoridades portuárias ajustam contratos após meses de volatilidade. O efeito principal não mira \(state.country.name), mas muda preços, rotas e prazos de entrega que todos os governos terão de absorver.",
                .economy,
                .marketConfidence,
                -2
            ),
            (
                "Uma coalizão média testa disciplina diplomática",
                "Estados que não lideram o sistema começam a votar em bloco em fóruns multilaterais. A mudança é pequena no mapa, mas grande na negociação: concessões futuras ficam mais caras.",
                .diplomacy,
                .diplomaticLeverage,
                -1
            ),
            (
                "Incidente marítimo aumenta custos de segurança",
                "Um choque entre patrulhas e navios comerciais não explode em guerra, mas eleva seguros, mobiliza comandos regionais e cria pressão por escoltas. O mundo fica menos previsível.",
                .crisis,
                .worldTension,
                3
            ),
        ]
        let selected = templates[(state.round + index) % templates.count]
        let eventId = "world-\(date)-\(index)-\(state.round)"

        return NativeCampaignEvent(
            date: date,
            description: selected.1,
            id: eventId,
            importance: selected.4 >= 3 ? .major : .minor,
            kind: selected.2,
            linkedActionIDs: [],
            notable: selected.4 >= 3,
            playerRelated: false,
            strategicEffects: [
                NativeStrategicEffect(
                    date: date,
                    eventId: eventId,
                    id: "\(eventId)-effect",
                    magnitude: selected.4,
                    summary: "Evento externo altera pressões sistêmicas sem tornar o jogador o centro de tudo.",
                    target: "International system",
                    track: selected.3
                ),
            ],
            title: selected.0
        )
    }

    private static func secondOrderEvent(for state: NativeCampaignState, date: String, index: Int) -> NativeCampaignEvent {
        let eventId = "domestic-\(date)-\(index)-\(state.round)"
        return NativeCampaignEvent(
            date: date,
            description: "Sem uma ordem concreta do jogador, ministérios, parlamento e setor produtivo interpretam a falta de direção como sinal. A consequência é menos espetacular, mas real: agendas concorrentes ocupam espaço político.",
            id: eventId,
            importance: .minor,
            kind: .action,
            linkedActionIDs: [],
            notable: false,
            playerRelated: true,
            strategicEffects: [
                NativeStrategicEffect(
                    date: date,
                    eventId: eventId,
                    id: "\(eventId)-stability",
                    magnitude: -1,
                    summary: "Ausência de prioridade reduz coesão administrativa.",
                    target: state.country.name,
                    track: .internalStability
                ),
            ],
            title: "A falta de prioridade cobra preço administrativo"
        )
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

    private static func classify(_ text: String) -> (
        kind: NativeEventKind,
        importance: NativeEventImportance,
        primaryTrack: NativeStrategicTrack,
        primaryMagnitude: Int,
        primarySummary: String,
        frictionTrack: NativeStrategicTrack,
        frictionMagnitude: Int,
        frictionSummary: String
    ) {
        let lower = text.lowercased()
        if lower.contains("nav") || lower.contains("milit") || lower.contains("army") || lower.contains("defen") || lower.contains("segur") {
            return (.crisis, .major, .militaryReadiness, 3, "Capacidade operacional sobe, mas passa a ser observada por rivais.", .securityAnxiety, 2, "Postura militar aumenta percepção regional de risco.")
        }
        if lower.contains("trade") || lower.contains("market") || lower.contains("econom") || lower.contains("indust") || lower.contains("energia") {
            return (.economy, .major, .economicResilience, 3, "Instrumentos econômicos criam amortecedores reais para choques futuros.", .marketConfidence, 1, "Mercados precificam execução, não intenção.")
        }
        if lower.contains("diplom") || lower.contains("treat") || lower.contains("alliance") || lower.contains("talk") || lower.contains("negoti") {
            return (.diplomacy, .major, .diplomaticLeverage, 3, "Canal diplomático reduz incerteza e cria termos verificáveis.", .worldTension, -1, "Sinalização clara reduz risco de erro de cálculo.")
        }
        return (.action, .minor, .internalStability, 2, "Prioridade clara melhora coordenação interna.", .worldTension, 1, "Atores externos aguardam sinais concretos de continuidade.")
    }

    private static func clamp(_ value: Int) -> Int {
        max(0, min(100, value))
    }
}
