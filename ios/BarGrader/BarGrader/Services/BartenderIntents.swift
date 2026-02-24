import AppIntents
import Foundation

// MARK: - Ask Bartender Intent

/// Siri Shortcut: "Ask Bartender" – starts recording so the user can dictate a bar exam question.
struct AskBartenderIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Bartender"
    static var description = IntentDescription(
        "Start recording a bar exam question for Bartender to grade using IRAC methodology."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let state = AppState.shared
        if !state.isRecording {
            state.startRecording()
        }
        return .result()
    }
}

// MARK: - Stop Recording Intent

/// Siri Shortcut: "Stop Bartender" – stops the current recording and submits the question.
struct StopBartenderIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Bartender"
    static var description = IntentDescription(
        "Stop recording and submit the current question to Bartender."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let state = AppState.shared
        if state.isRecording {
            state.stopRecording()
        }
        return .result()
    }
}

// MARK: - Cycle Mode Intent

/// Siri Shortcut: "Switch Bartender Mode" – cycles between Essay, Outline, and MBE modes.
struct CycleBartenderModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Bartender Mode"
    static var description = IntentDescription(
        "Cycle Bartender between Essay, Outline, and MBE grading modes."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.cycleMode()
        return .result()
    }
}

// MARK: - App Shortcuts Provider

/// Registers Bartender shortcuts with Siri and the Shortcuts app.
struct BartenderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskBartenderIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Hey \(.applicationName)",
                "Start recording with \(.applicationName)",
                "\(.applicationName) listen"
            ],
            shortTitle: "Ask Bartender",
            systemImageName: "mic.fill"
        )

        AppShortcut(
            intent: StopBartenderIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "\(.applicationName) stop recording"
            ],
            shortTitle: "Stop Bartender",
            systemImageName: "stop.circle.fill"
        )

        AppShortcut(
            intent: CycleBartenderModeIntent(),
            phrases: [
                "Switch \(.applicationName) mode",
                "\(.applicationName) next mode"
            ],
            shortTitle: "Switch Mode",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
