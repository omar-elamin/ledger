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
DEVICE_ID=$(
  xcrun simctl list devices available |
  sed -nE '/iPhone/s/.*\(([0-9A-Fa-f-]{36})\) \((Booted|Shutdown)\)[[:space:]]*$/\1/p' |
  head -n 1
)
```

Run the deterministic core suite:

```bash
xcodegen generate
xcodebuild -project Ledger.xcodeproj -scheme "Ledger Core" -destination "id=$DEVICE_ID" test
```

Run the simulator UI smoke suite:

```bash
xcodebuild -project Ledger.xcodeproj -scheme "Ledger UI" -destination "id=$DEVICE_ID" test
```

Run the manual heavy multi-day hierarchical memory E2E suite:

```bash
LEDGER_RUN_MEMORY_E2E=1 \
xcodebuild -project Ledger.xcodeproj -scheme "Ledger UI" -destination "id=$DEVICE_ID" test
```

Run the live Anthropic smoke suite, including memory-maintainer prompt smokes:

```bash
LEDGER_RUN_LIVE_API_TESTS=1 \
xcodebuild -project Ledger.xcodeproj -scheme "Ledger Live API" -destination "id=$DEVICE_ID" test
```

The live suite skips unless both `LEDGER_RUN_LIVE_API_TESTS=1` and a non-empty
`Ledger/Secrets.swift` key are present.

## License

Ledger is licensed under the GNU Affero General Public License v3.0. See
`LICENSE` for the full terms.

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
