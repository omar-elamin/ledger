import SwiftUI
import Observation

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let appEnvironment: LedgerAppEnvironment

    @State private var selectedTab: Int = 1
    @State private var dayAnchorController: DayAnchorController
    @State private var chatViewModel: ChatViewModel
    @State private var memoryMaintenanceScheduler: MemoryMaintenanceScheduler
    @State private var testHarness: LedgerTestHarness?

    init(appEnvironment: LedgerAppEnvironment) {
        self.appEnvironment = appEnvironment
        _dayAnchorController = State(initialValue: appEnvironment.makeDayAnchorController())
        _chatViewModel = State(initialValue: appEnvironment.makeChatViewModel())
        _memoryMaintenanceScheduler = State(initialValue: appEnvironment.memoryMaintenanceScheduler)
        _testHarness = State(initialValue: appEnvironment.makeTestHarness())
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayLogView(dayAnchorController: dayAnchorController)
                .tag(0)
            ChatView(viewModel: chatViewModel)
                .tag(1)
            HistoryView(dayAnchorController: dayAnchorController)
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(.keyboard)
        .background(Color.ledgerBg)
        .overlay(alignment: .topTrailing) {
            if let testHarness {
                LedgerTestHarnessControls(
                    harness: testHarness,
                    dayAnchorController: dayAnchorController
                )
                .padding(.top, 8)
                .padding(.trailing, 8)
            }
        }
        .onAppear {
            dayAnchorController.handleScenePhaseChange(scenePhase)
            if appEnvironment.shouldAutoRunMaintenance {
                memoryMaintenanceScheduler.handleScenePhaseChange(scenePhase)
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            dayAnchorController.handleScenePhaseChange(newValue)
            if appEnvironment.shouldAutoRunMaintenance {
                memoryMaintenanceScheduler.handleScenePhaseChange(newValue)
            }
        }
    }
}

private struct LedgerTestHarnessControls: View {
    @Bindable var harness: LedgerTestHarness
    let dayAnchorController: DayAnchorController

    @State private var nowInput = ""
    @State private var dayDeltaInput = "1"

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextField("ISO8601", text: $nowInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .font(.caption.monospaced())
                .accessibilityIdentifier("testHarness.nowInput")

            Button("Set Time") {
                harness.setNow(nowInput)
                dayAnchorController.refreshAnchor()
            }
            .accessibilityIdentifier("testHarness.setNowButton")

            TextField("Days", text: $dayDeltaInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .font(.caption.monospaced())
                .keyboardType(.numberPad)
                .accessibilityIdentifier("testHarness.advanceDaysInput")

            Button("Advance Days") {
                let value = Int(dayDeltaInput) ?? 0
                harness.advanceDays(value)
                dayAnchorController.refreshAnchor()
            }
            .accessibilityIdentifier("testHarness.advanceDaysButton")

            Button("Run Nightly") {
                Task {
                    await harness.runNightly(force: true)
                }
            }
            .accessibilityIdentifier("testHarness.runNightlyButton")

            Button("Reset Timestamps") {
                harness.resetMaintenanceTimestamps()
            }
            .accessibilityIdentifier("testHarness.resetTimestampsButton")

            Button("Dump Snapshot") {
                harness.dumpMemorySnapshot()
            }
            .accessibilityIdentifier("testHarness.dumpSnapshotButton")

            Text(harness.statusMessage)
                .font(.caption.monospaced())
                .foregroundStyle(Color.ledgerTextSecondary)
                .accessibilityIdentifier("testHarness.status")
        }
        .padding(8)
        .background(Color.black.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
