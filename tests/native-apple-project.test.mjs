import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const project = readFileSync("Apple/PaxHistoriaApple.xcodeproj/project.pbxproj", "utf8");
const contentView = readFileSync("Apple/PaxHistoriaApple/ContentView.swift", "utf8");
const nativeService = readFileSync("Apple/PaxHistoriaApple/NativeFoundationModelService.swift", "utf8");
const nativeEngine = readFileSync("Apple/PaxHistoriaApple/NativeGameEngine.swift", "utf8");

test("Apple targets are SwiftUI-native and no longer build the WebView shell", () => {
  assert.doesNotMatch(project, /WebGameView\.swift in Sources/);
  assert.doesNotMatch(project, /FoundationModelBridge\.swift in Sources/);
  assert.doesNotMatch(project, /dist in Resources/);
  assert.doesNotMatch(contentView, /NativeWebGameView|WKWebView|WebKit/);
  assert.match(contentView, /NativeGameView/);
});

test("native Apple game calls the Foundation Models responder directly", () => {
  assert.match(nativeService, /AppleFoundationModelResponder/);
  assert.match(nativeService, /nativeJumpForward/);
  assert.match(nativeService, /nativeStatusCheck/);
  assert.match(nativeService, /responseFormat: "json"/);
});

test("native Apple game uses guided generation inside the Apple context window", () => {
  assert.match(nativeService, /@Generable/);
  assert.match(nativeService, /generating: AppleNativeGeneratedTurn\.self/);
  assert.match(nativeService, /includeSchemaInPrompt: true/);
  assert.match(nativeService, /contextWindowTokens: 4096/);
  assert.match(nativeService, /maximumResponseTokens: 760/);
});

test("native event engine enforces world events and strategic consequences", () => {
  assert.match(nativeEngine, /independentWorldEvent/);
  assert.match(nativeEngine, /playerRelated: false/);
  assert.match(nativeEngine, /!events\.contains\(where: \{ !\$0\.playerRelated \}\)/);
  assert.match(nativeEngine, /strategicEffects/);
  assert.match(nativeEngine, /worldTension/);
  assert.match(nativeEngine, /internalStability/);
});
