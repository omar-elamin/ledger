import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let appEnvironment: LedgerAppEnvironment

    @State private var selectedTab: Int = 1
    @State private var dayAnchorController: DayAnchorController
    @State private var chatViewModel: ChatViewModel

    init(appEnvironment: LedgerAppEnvironment = LedgerAppEnvironment.bootstrap()) {
        self.appEnvironment = appEnvironment
        _dayAnchorController = State(initialValue: appEnvironment.makeDayAnchorController())
        _chatViewModel = State(initialValue: appEnvironment.makeChatViewModel())
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
        .onAppear {
            dayAnchorController.handleScenePhaseChange(scenePhase)
        }
        .onChange(of: scenePhase) { _, newValue in
            dayAnchorController.handleScenePhaseChange(newValue)
        }
    }
}
