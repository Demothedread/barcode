import Foundation

/// On-device LLM inference — STUBBED for server-first deployment.
/// The LLM.swift SPM package is not included to keep build times fast.
/// All AI work routes through the Railway backend.
@MainActor
final class LocalLLMService: ObservableObject {
    static let shared = LocalLLMService()

    @Published var isModelLoaded = false
    @Published var isGenerating  = false
    @Published var loadError: String?
    @Published var downloadProgress: Double = 0

    static let bundledModelName = "bargrader-model.gguf"

    private init() {}

    static let barExamSystemPrompt = """
    You are BarGrader, a California Bar Exam tutor. Answer concisely and accurately.
    Use IRAC format for essays. Cite specific legal rules and tests by name.
    """

    func preloadModel() {
        loadError = "Local model disabled — using server mode"
        print("[LocalLLM] Stubbed — server-first deployment")
    }

    func stream(question: String, mode: String = "essay") -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LocalLLMError.modelNotLoaded)
        }
    }

    nonisolated static func buildPrompt(question: String, mode: String) -> String {
        let instruction: String
        switch mode {
        case "mbe":
            instruction = "[MBE MODE] Answer with the letter first, then a 1-2 sentence explanation."
        case "outline":
            instruction = "[OUTLINE MODE] Bullet-point the issues with brief rule statements."
        default:
            instruction = "[ESSAY MODE] Use IRAC format: Issue, Rule, Application, Conclusion."
        }
        return "\(instruction)\n\n\(question)"
    }

    private static func modeInstruction(for mode: String) -> String {
        switch mode {
        case "mbe":
            return "[MBE MODE] Answer with the letter first, then a 1-2 sentence explanation."
        case "outline":
            return "[OUTLINE MODE] Bullet-point the issues with brief rule statements."
        default:
            return "[ESSAY MODE] Use IRAC format: Issue, Rule, Application, Conclusion."
        }
    }
}

enum LocalLLMError: LocalizedError {
    case modelNotLoaded
    case generationFailed(String)
    // swiftllama not installed kept for compat
    case swiftLlamaNotInstalled

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Local model not available — connect to server for AI features."
        case .generationFailed(let detail):
            return "Local generation failed: \(detail)"
        case .swiftLlamaNotInstalled:
            return "SwiftLlama not installed."
        }
    }
}
