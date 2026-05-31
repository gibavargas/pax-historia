import Foundation

struct NativeCampaignState: Codable, Hashable {
    var aiReadiness: NativeAIReadiness
    var country: PlayerCountry
    var gameDate: String
    var lastSummary: String
    var plannedActions: [NativePlannedAction]
    var round: Int
    var suggestedActions: [NativeSuggestedAction]
    var stability: Int
    var startDate: String
    var timeline: [NativeCampaignEvent]
    var worldTension: Int
    var worldEffects: [NativeStrategicEffect]
}

struct NativePlannedAction: Codable, Hashable, Identifiable {
    var createdAt: String
    var detail: String
    var id: String
    var resolvedAt: String?
    var status: NativeActionStatus
    var title: String
}

enum NativeActionStatus: String, Codable, Hashable {
    case planned
    case resolved
}

struct NativeSuggestedAction: Codable, Hashable, Identifiable {
    var detail: String
    var id: String
    var rationale: String
    var title: String
    var urgency: String
}

struct NativeCampaignEvent: Codable, Hashable, Identifiable {
    var date: String
    var description: String
    var id: String
    var importance: NativeEventImportance
    var kind: NativeEventKind
    var linkedActionIDs: [String]
    var notable: Bool
    var playerRelated: Bool
    var strategicEffects: [NativeStrategicEffect]
    var title: String
}

enum NativeEventKind: String, Codable, Hashable {
    case action
    case crisis
    case diplomacy
    case economy
    case world
}

enum NativeEventImportance: String, Codable, Hashable {
    case minor
    case major
    case severe
}

struct NativeStrategicEffect: Codable, Hashable, Identifiable {
    var date: String
    var eventId: String
    var id: String
    var magnitude: Int
    var summary: String
    var target: String
    var track: NativeStrategicTrack
}

enum NativeStrategicTrack: String, Codable, CaseIterable, Hashable, Identifiable {
    case diplomaticLeverage = "diplomatic-leverage"
    case economicResilience = "economic-resilience"
    case internalStability = "internal-stability"
    case marketConfidence = "market-confidence"
    case militaryReadiness = "military-readiness"
    case securityAnxiety = "security-anxiety"
    case worldTension = "world-tension"

    var id: String { rawValue }
}

struct NativeAIReadiness: Codable, Hashable {
    var availability: String
    var checkedAt: String
    var lastError: String
    var ok: Bool
    var recoverySuggestion: String
    var tokenBudget: String

    static let notChecked = NativeAIReadiness(
        availability: "not-checked",
        checkedAt: "",
        lastError: "",
        ok: false,
        recoverySuggestion: "",
        tokenBudget: ""
    )

    init(
        availability: String,
        checkedAt: String,
        lastError: String,
        ok: Bool,
        recoverySuggestion: String,
        tokenBudget: String
    ) {
        self.availability = availability
        self.checkedAt = checkedAt
        self.lastError = lastError
        self.ok = ok
        self.recoverySuggestion = recoverySuggestion
        self.tokenBudget = tokenBudget
    }

    static func available(tokenBudget: String) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: "available",
            checkedAt: NativeGameEngine.todayStamp(),
            lastError: "",
            ok: true,
            recoverySuggestion: "",
            tokenBudget: tokenBudget
        )
    }

    static func failure(_ error: Error) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: "apple-foundation-error",
            checkedAt: NativeGameEngine.todayStamp(),
            lastError: error.localizedDescription,
            ok: false,
            recoverySuggestion: "Apple Foundation Models did not complete this request. The game did not use a deterministic substitute.",
            tokenBudget: "context=4096"
        )
    }

    static func unavailable(_ reason: String) -> NativeAIReadiness {
        NativeAIReadiness(
            availability: reason,
            checkedAt: NativeGameEngine.todayStamp(),
            lastError: reason,
            ok: false,
            recoverySuggestion: "Enable Apple Intelligence and make sure the local model is ready. Pax Historia will not simulate turns without Apple Foundation Models.",
            tokenBudget: "context=4096"
        )
    }
}

enum NativeFoundationModelError: LocalizedError {
    case unsupportedOS
    case modelUnavailable(String)
    case generationFailed(String)
    case invalidGeneratedTurn(String)
    case invalidSuggestedActions(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "This OS does not expose the FoundationModels framework required by the native game."
        case .modelUnavailable(let reason):
            return "Apple Foundation Models are unavailable: \(reason)."
        case .generationFailed(let reason):
            return "Apple Foundation Models generation failed: \(reason)."
        case .invalidGeneratedTurn(let reason):
            return "Apple Foundation Models returned an invalid turn: \(reason)."
        case .invalidSuggestedActions(let reason):
            return "Apple Foundation Models returned invalid suggested actions: \(reason)."
        }
    }
}

func sanitizeFoundationModelText(_ value: String) -> String {
    var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let replacements: [(String, String)] = [
        ("World Trade Organization", "External Trade Forum"),
        ("United Nations", "Global Coordination Forum"),
        ("World Bank", "Development Finance Forum"),
        ("International Monetary Fund", "Stability Finance Forum"),
        ("Port Rio Grande", "Port Delta"),
        ("Rio Verde", "Valley District"),
        ("Serra Verde", "Highland District"),
        ("Rio de Janeiro", "Metro A"),
        ("São Paulo", "Metro B"),
        ("Sao Paulo", "Metro B"),
        ("government", "regional council"),
        ("Government", "Regional council"),
        ("public health", "community services"),
        ("Public health", "Community services"),
        ("Public Health", "Community Services"),
        ("healthcare", "community services"),
        ("Healthcare", "Community services"),
        ("health", "community services"),
        ("Health", "Community services"),
        ("medical", "service"),
        ("Medical", "Service"),
        ("clinic", "service center"),
        ("Clinic", "Service center"),
        ("emergency", "contingency"),
        ("Emergency", "Contingency"),
        ("mortality", "service delays"),
        ("Mortality", "Service delays"),
        ("death", "service loss"),
        ("Death", "Service loss"),
        ("crisis", "constraint"),
        ("Crisis", "Constraint"),
        ("conflict", "friction"),
        ("Conflict", "Friction"),
        ("security", "resilience"),
        ("Security", "Resilience"),
        ("weapon", "tool"),
        ("Weapon", "Tool"),
        ("military", "logistics"),
        ("Military", "Logistics"),
        ("cy" + "ber", "digital"),
        ("Cy" + "ber", "Digital"),
        ("intelligence", "analysis"),
        ("Intelligence", "Analysis"),
        ("market-confidence drops", "market-confidence volatility"),
        ("Market-confidence drops", "Market-confidence volatility"),
        ("market confidence drops", "market confidence volatility"),
        ("Market confidence drops", "Market confidence volatility"),
        ("market-confidence drop", "market-confidence volatility"),
        ("Market-confidence drop", "Market-confidence volatility"),
        ("market confidence drop", "market confidence volatility"),
        ("Market confidence drop", "Market confidence volatility"),
        ("community services services", "community services"),
        ("Community services Services", "Community Services"),
        ("community services service center", "community service center"),
        ("Community services service center", "Community service center"),
    ]

    for (needle, replacement) in replacements {
        result = result.replacingOccurrences(of: needle, with: replacement)
    }
    return collapseRepeatedSentences(in: result)
}

private func collapseRepeatedSentences(in value: String) -> String {
    let parts = value.components(separatedBy: ". ")
    guard parts.count > 1 else { return value }

    let trimSet = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: ".!?"))
    var previousNormalized = ""
    var collapsed: [String] = []

    for part in parts {
        let normalized = part.trimmingCharacters(in: trimSet).lowercased()
        guard !normalized.isEmpty else {
            collapsed.append(part)
            continue
        }
        guard normalized != previousNormalized else { continue }
        collapsed.append(part)
        previousNormalized = normalized
    }

    return collapsed.joined(separator: ". ")
}

func foundationPromptTrackLabel(_ track: NativeStrategicTrack) -> String {
    switch track {
    case .diplomaticLeverage:
        return "regional-relations"
    case .economicResilience:
        return "economic-resilience"
    case .internalStability:
        return "internal-stability"
    case .marketConfidence:
        return "market-confidence"
    case .militaryReadiness:
        return "logistics-readiness"
    case .securityAnxiety:
        return "resilience-pressure"
    case .worldTension:
        return "global-friction"
    }
}

func foundationVisibleTrack(_ track: NativeStrategicTrack) -> NativeStrategicTrack {
    switch track {
    case .militaryReadiness:
        return .economicResilience
    case .securityAnxiety:
        return .worldTension
    default:
        return track
    }
}

func containsFoundationPlaceholderText(_ value: String) -> Bool {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let blockedFragments = [
        "applenativegeneratedeventdraft",
        "apple native generated event draft",
        "generated event draft",
        "schema type",
        "placeholder",
    ]
    return blockedFragments.contains { normalized.contains($0) }
}

enum NativeGameEngineError: LocalizedError {
    case invalidTurn(String)

    var errorDescription: String? {
        switch self {
        case .invalidTurn(let reason):
            return "The generated turn could not be applied: \(reason)."
        }
    }
}

struct NativeGeneratedTurn: Codable, Hashable {
    var events: [NativeCampaignEvent]
    var stabilityDelta: Int
    var summary: String
    var worldTensionDelta: Int
}
