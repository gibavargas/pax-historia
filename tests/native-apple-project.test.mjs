import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const project = readFileSync("Apple/PaxHistoriaApple.xcodeproj/project.pbxproj", "utf8");
const contentView = readFileSync("Apple/PaxHistoriaApple/ContentView.swift", "utf8");
const nativeService = readFileSync("Apple/PaxHistoriaApple/NativeFoundationModelService.swift", "utf8");
const nativeEngine = readFileSync("Apple/PaxHistoriaApple/NativeGameEngine.swift", "utf8");
const nativeModels = readFileSync("Apple/PaxHistoriaApple/NativeCampaignModels.swift", "utf8");
const nativeView = readFileSync("Apple/PaxHistoriaApple/NativeGameView.swift", "utf8");

test("Apple targets are SwiftUI-native and no longer build the WebView shell", () => {
  assert.doesNotMatch(project, /WebGameView\.swift in Sources/);
  assert.doesNotMatch(project, /FoundationModelBridge\.swift in Sources/);
  assert.doesNotMatch(project, /dist in Resources/);
  assert.doesNotMatch(contentView, /NativeWebGameView|WKWebView|WebKit/);
  assert.match(contentView, /NativeGameView/);
});

test("native Apple game calls Foundation Models directly without responder fallback", () => {
  assert.doesNotMatch(project, /AppleAIModels\.swift in Sources|AppleFoundationModelResponder\.swift in Sources/);
  assert.doesNotMatch(nativeService, /AppleFoundationModelResponder|fallbackResponse|fallbackText|fallbackUsed/);
  assert.doesNotMatch(nativeModels, /fallbackUsed/);
  assert.doesNotMatch(nativeEngine, /fallbackTurn|generatedTurn\(from rawText/);
  assert.match(nativeService, /generateTurn\(for state: NativeCampaignState, months: Int\) async throws/);
  assert.match(nativeService, /SystemLanguageModel\.default/);
});

test("native Apple game uses guided generation inside the Apple context window", () => {
  assert.match(nativeService, /@Generable/);
  assert.match(nativeService, /generateSlicedTurn/);
  assert.match(nativeService, /generating: AppleNativeGeneratedEventDraft\.self/);
  assert.match(nativeService, /generating: AppleNativeTurnSummary\.self/);
  assert.match(nativeService, /makeSuggestionPrompt/);
  assert.match(nativeService, /generating: AppleNativeSuggestedAction\.self/);
  assert.match(nativeService, /includeSchemaInPrompt: true/);
  assert.match(nativeService, /context=4096/);
  assert.match(nativeService, /maximumResponseTokens: 260/);
  assert.match(nativeService, /maximumResponseTokens: 180/);
  assert.doesNotMatch(nativeService, /AppleNativeSuggestedActionSet/);
  assert.doesNotMatch(nativeService, /weapons|cyber|coercion|surveillance|military-readiness|security-anxiety/);
});

test("native event engine enforces world events and strategic consequences", () => {
  assert.match(nativeEngine, /turn\.events\.contains\(where: \{ !\$0\.playerRelated \}\)/);
  assert.match(nativeEngine, /throw NativeGameEngineError\.invalidTurn/);
  assert.match(nativeEngine, /strategicEffects/);
  assert.match(nativeEngine, /worldTension/);
  assert.match(nativeEngine, /internalStability/);
});

test("native Apple game renders a map and Apple-generated action suggestions", () => {
  assert.match(nativeView, /import MapKit/);
  assert.match(nativeView, /Map\(initialPosition:/);
  assert.match(nativeView, /native-strategic-map/);
  assert.match(nativeView, /Apple-suggested actions/);
  assert.match(nativeView, /refreshSuggestedActions/);
});
