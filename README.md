# Ledger

A conversational personal-health-coach iOS app for iOS 17+. The app now ships
with real Anthropic streaming chat, silent tool calls into SwiftData, persisted
chat/log history, deterministic simulator tests, and separate opt-in live API
smoke tests.

## Build

```bash
brew install xcodegen          # one-time
xcodegen generate              # produces Ledger.xcodeproj
open Ledger.xcodeproj
```

Build and run to any iPhone simulator on iOS 17+.

## Local Secrets

Create `Ledger/Secrets.swift` locally:

```swift
enum Secrets {
    static let anthropicAPIKey = "sk-ant-..."
}
```

If the file is missing or the key is empty, the app still launches and chat
falls back to the missing-key message.

## Tests

Resolve a simulator once per shell:

```bash
DEVICE_ID=$(xcrun simctl list devices available | awk -F '[()]' '
  /iPhone .*Booted/ { print $(NF-1); exit }
  /iPhone .*Shutdown/ { print $(NF-1); exit }
')
```

Run the deterministic unit/integration + UI suite:

```bash
xcodegen generate
xcodebuild -project Ledger.xcodeproj -scheme Ledger -destination "id=$DEVICE_ID" test
```

Run only the simulator UI tests:

```bash
xcodebuild -project Ledger.xcodeproj -scheme Ledger -destination "id=$DEVICE_ID" -only-testing:LedgerUITests test
```

Run the live Anthropic smoke suite:

```bash
LEDGER_RUN_LIVE_API_TESTS=1 \
xcodebuild -project Ledger.xcodeproj -scheme "Ledger Live API" -destination "id=$DEVICE_ID" test
```

The live suite skips unless both `LEDGER_RUN_LIVE_API_TESTS=1` and a non-empty
`Ledger/Secrets.swift` key are present.

### First-time Xcode setup

If the build fails with `No available simulator runtimes for platform
iphonesimulator`, open Xcode → Settings → Platforms → `+` → **iOS** and
download a simulator runtime. Then create an iPhone simulator via
Xcode → Window → Devices and Simulators.

## Structure

```text
Ledger/
  LedgerApp.swift        app entry
  ContentView.swift      3-screen page TabView
  Models/                UI models, SwiftData models, history timeline
  Services/              Claude client, prompts, tools, streaming helpers
  ViewModels/            chat orchestration and day-boundary controller
  Theme/                 Colors + Typography
  Components/            MessageBubble, ChatInput
  Views/                 ChatView, TodayLogView, HistoryView
LedgerTests/             deterministic unit + integration tests
LedgerUITests/           simulator end-to-end tests
LedgerLiveAPITests/      opt-in live Anthropic smoke tests
```
