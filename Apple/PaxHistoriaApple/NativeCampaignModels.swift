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
