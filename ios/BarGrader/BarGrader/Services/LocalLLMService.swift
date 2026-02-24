import Foundation

/// On-device LLM inference via llama.cpp (SwiftLlama wrapper).
///
/// This service provides **offline fallback** when the BarGrader server is
/// unreachable.  It loads a small quantised GGUF model bundled with the app
/// and streams tokens back via a callback.
///
/// Quality is intentionally lower than the server (GPT-4o / Gemini) — this
/// is emergency-only, "better than nothing" mode.
///
/// ## Model Requirements
/// - Format: GGUF (Q4_K_M or Q4_K_S quantisation recommended)
/// - Size: ≤ 2 GB on disk to avoid App Store limits and RAM pressure
/// - Recommended: SmolLM2-1.7B-Q4_K_M or Phi-3.5-mini-Q4_K_M
/// - Place the .gguf file in the app bundle (add to Xcode target)
///
/// ## Usage
/// ```swift
/// let llm = LocalLLMService.shared
/// if llm.isModelLoaded {
///     for try await token in llm.stream(prompt: "What is negligence?") {
///         print(token, terminator: "")
///     }
/// }
/// ```
@MainActor
final class LocalLLMService: ObservableObject {
    static let shared = LocalLLMService()
    
    // MARK: - State
    @Published var isModelLoaded = false
    @Published var isGenerating = false
    @Published var loadError: String?
    
    // MARK: - Configuration
    
    /// File name of the GGUF model in the app bundle (no path — just "model.gguf")
    static let bundledModelName = "bargrader-model.gguf"
    
    /// Max context window (tokens). Keep small to save RAM on iPhone.
    static let contextSize: Int = 2048
    
    /// Max tokens to generate per response.
    static let maxTokens: Int = 512
    
    /// Temperature for generation (low = more deterministic for legal answers).
    static let temperature: Float = 0.2
    
    // MARK: - Bar Exam System Prompt (baked in — no RAG needed offline)
    
    /// Compressed bar-exam knowledge baked directly into the system prompt.
    /// This acts as "pre-RAG" — the model always has this context available,
    /// eliminating the need for a vector store on-device.
    static let barExamSystemPrompt = """
    You are BarGrader, a California Bar Exam tutor. Answer concisely and accurately.
    
    CORE LEGAL FRAMEWORKS (California Bar Exam):
    
    CONTRACTS: Offer (manifestation of willingness), Acceptance (mirror image/UCC §2-207), \
    Consideration (bargained-for exchange), Defenses (SOF for land/marriage/1yr+/goods≥$500/surety, \
    unconscionability, duress, undue influence, misrepresentation, mistake), \
    Parol Evidence Rule (no prior/contemporaneous contradictions, exceptions: ambiguity, fraud, \
    condition precedent, collateral agreement), Performance/Breach (material vs minor, \
    anticipatory repudiation, substantial performance), Remedies (expectation, reliance, \
    restitution, specific performance, liquidated damages).
    
    TORTS: Intentional (battery=harmful/offensive contact, assault=apprehension, \
    false imprisonment=bounded area, IIED=extreme+outrageous), Negligence (duty=reasonable person, \
    breach=BPL/custom/statute, causation=but-for+proximate/foreseeability, damages=actual harm), \
    Strict Liability (abnormally dangerous activity/products=manufacturing+design+warning defects), \
    Defenses (comparative fault CA=pure, assumption of risk, contrib negligence).
    
    CONSTITUTIONAL LAW: State action required. Due Process (substantive=fundamental rights+strict scrutiny, \
    procedural=Mathews balancing). Equal Protection (strict=race/national origin, \
    intermediate=gender, rational basis=economic). First Amendment (content-based=strict scrutiny, \
    content-neutral=intermediate, commercial speech=Central Hudson, obscenity=Miller test). \
    Commerce Clause (substantial effect on interstate commerce). Takings (per se=physical occupation, \
    regulatory=Penn Central factors, just compensation required).
    
    CRIMINAL LAW: Actus reus + mens rea (specific intent=attempt/solicitation/conspiracy/burglary, \
    general intent=battery/rape/kidnapping, malice=murder/arson, strict liability=statutory rape). \
    Homicide (1st degree=premeditation+deliberation, 2nd degree=malice, voluntary MS=heat of passion, \
    involuntary MS=criminal negligence, felony murder=BARRK felonies). \
    Inchoate crimes (attempt=substantial step, conspiracy=agreement+overt act, solicitation=asking). \
    Defenses (self-defense=reasonable force, insanity=M'Naghten/irresistible impulse/MPC, \
    intoxication=voluntary negates specific intent only).
    
    EVIDENCE: Relevance (FRE 401=tendency to prove), Character (generally inadmissible, \
    exceptions=D in criminal/victim/witness impeachment), Hearsay (out-of-court statement for truth, \
    exemptions=prior testimony/admission, exceptions=present sense impression/excited utterance/ \
    state of mind/medical diagnosis/business records/dying declaration), \
    Privileges (attorney-client, spousal immunity, marital communications).
    
    REAL PROPERTY: Estates (fee simple/life estate/defeasible fees), Future interests \
    (reversion/remainder/executory interest), Concurrent ownership (JT=right of survivorship, \
    TIC=no survivorship, community property=CA default), Landlord-Tenant \
    (tenancy for years/periodic/at will/at sufferance), Recording acts \
    (race/notice/race-notice=CA is race-notice).
    
    COMMUNITY PROPERTY (CA): Presumption=community property during marriage. \
    SP=before marriage/gift/inheritance/after separation. Transmutation=writing required. \
    Commingling=tracing to source. Division=equal 50/50 at dissolution.
    
    CIVIL PROCEDURE: Personal jurisdiction (general=domicile/systematic contacts, \
    specific=minimum contacts+relatedness+reasonableness), SMJ (federal question/diversity≥$75k), \
    Erie doctrine (substantive=state law, procedural=federal rules), \
    Claim/issue preclusion, Joinder (Rule 18=permissive claims, Rule 20=permissive parties).
    
    ANSWER FORMAT:
    - For MBE/exam mode: Give the answer letter first, then 1-2 sentence explanation.
    - For essay questions: Use IRAC format (Issue, Rule, Application, Conclusion).
    - For outline mode: Bullet-point issues with rule statements only.
    - Always cite the specific legal rule or test by name.
    - Be concise. Quality > quantity.
    """
    
    // MARK: - Private
    
    /// Reference to the loaded llama.cpp model (opaque — depends on SwiftLlama)
    private var llamaInstance: Any?  // SwiftLlama type when loaded
    
    private init() {}
    
    // MARK: - Model Loading
    
    /// Attempt to load the bundled GGUF model. Call once at app startup.
    /// This is intentionally non-blocking — model loads on a background thread.
    func preloadModel() {
        guard !isModelLoaded else { return }
        
        guard let modelURL = modelFileURL() else {
            loadError = "Model file '\(Self.bundledModelName)' not found in app bundle"
            print("[LocalLLM] \(loadError!)")
            return
        }
        
        print("[LocalLLM] Pre-loading model from: \(modelURL.path)")
        
        Task.detached(priority: .utility) { [weak self] in
            do {
                // Dynamic import — SwiftLlama must be added as a SPM dependency
                let llama = try await Self.loadLlamaModel(at: modelURL.path)
                
                await MainActor.run {
                    self?.llamaInstance = llama
                    self?.isModelLoaded = true
                    self?.loadError = nil
                    print("[LocalLLM] Model loaded successfully (\(Self.bundledModelName))")
                }
            } catch {
                await MainActor.run {
                    self?.loadError = "Model load failed: \(error.localizedDescription)"
                    print("[LocalLLM] \(self?.loadError ?? "")")
                }
            }
        }
    }
    
    /// Locate the .gguf file — first check Documents (user-downloaded), then app bundle.
    private func modelFileURL() -> URL? {
        // 1. Check Documents directory (for user-supplied models)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let docsModel = docs.appendingPathComponent(Self.bundledModelName)
        if FileManager.default.fileExists(atPath: docsModel.path) {
            print("[LocalLLM] Found model in Documents/")
            return docsModel
        }
        
        // 2. Check app bundle (compiled into the .ipa)
        if let bundled = Bundle.main.url(forResource: Self.bundledModelName.replacingOccurrences(of: ".gguf", with: ""),
                                          withExtension: "gguf") {
            print("[LocalLLM] Found model in app bundle")
            return bundled
        }
        
        return nil
    }
    
    // MARK: - Inference
    
    /// Stream tokens from the local model for a given question.
    /// Returns an AsyncThrowingStream of String tokens.
    func stream(question: String, mode: String = "essay") -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard isModelLoaded else {
                continuation.finish(throwing: LocalLLMError.modelNotLoaded)
                return
            }
            
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else {
                    continuation.finish()
                    return
                }
                
                await MainActor.run { self.isGenerating = true }
                
                let prompt = Self.buildPrompt(question: question, mode: mode)
                
                do {
                    // Use SwiftLlama's AsyncStream interface
                    let llama = await self.getLlamaInstance()
                    
                    if let llama = llama as? StreamableLLM {
                        for try await token in llama.stream(prompt: prompt, maxTokens: Self.maxTokens, temperature: Self.temperature) {
                            continuation.yield(token)
                        }
                    } else {
                        // Fallback: non-streaming (full response at once)
                        if let llama = llama as? CompletionLLM {
                            let response = try await llama.complete(prompt: prompt, maxTokens: Self.maxTokens, temperature: Self.temperature)
                            // Simulate streaming by chunking
                            let words = response.split(separator: " ")
                            for word in words {
                                continuation.yield(String(word) + " ")
                                try await Task.sleep(nanoseconds: 30_000_000) // ~30ms per word
                            }
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                
                await MainActor.run { self.isGenerating = false }
            }
        }
    }
    
    /// Build a ChatML-formatted prompt with the baked-in bar exam system context.
    nonisolated static func buildPrompt(question: String, mode: String) -> String {
        let modeInstruction: String
        switch mode {
        case "mbe":
            modeInstruction = "Answer in MBE exam mode: give the answer letter first, then a 1-2 sentence explanation. Be extremely concise."
        case "outline":
            modeInstruction = "Answer in outline mode: bullet-point the issues with brief rule statements. No full essay."
        default:
            modeInstruction = "Answer in IRAC essay format: Issue, Rule, Application, Conclusion. Be thorough but concise."
        }
        
        return """
        <|im_start|>system
        \(barExamSystemPrompt)
        
        \(modeInstruction)
        <|im_end|>
        <|im_start|>user
        \(question)
        <|im_end|>
        <|im_start|>assistant
        
        """
    }
    
    @MainActor
    private func getLlamaInstance() -> Any? {
        return llamaInstance
    }
    
    // MARK: - Static Model Loading (SwiftLlama)
    
    /// Load a GGUF model using SwiftLlama.
    /// This is isolated in a static method so it can run on a background thread.
    private static func loadLlamaModel(at path: String) async throws -> Any {
        // ── SwiftLlama integration ──
        // When you add SwiftLlama as a SPM dependency, replace this with:
        //
        //   import SwiftLlama
        //   let llama = try SwiftLlama(modelPath: path)
        //   return llama
        //
        // SwiftLlama conforms to our StreamableLLM protocol automatically
        // because it returns AsyncStream<String> from its start(for:) method.
        
        // SwiftLlama not yet integrated as SPM dependency
        throw LocalLLMError.swiftLlamaNotInstalled
    }
}

// MARK: - Protocols for LLM abstraction

/// Protocol for streaming LLM inference.
protocol StreamableLLM {
    func stream(prompt: String, maxTokens: Int, temperature: Float) -> AsyncThrowingStream<String, Error>
}

/// Protocol for non-streaming LLM inference.
protocol CompletionLLM {
    func complete(prompt: String, maxTokens: Int, temperature: Float) async throws -> String
}

// MARK: - Errors

enum LocalLLMError: LocalizedError {
    case modelNotLoaded
    case swiftLlamaNotInstalled
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Local model not loaded. Ensure bargrader-model.gguf is in the app bundle."
        case .swiftLlamaNotInstalled:
            return "SwiftLlama package not installed. Add it via SPM: https://github.com/ShenghaiWang/SwiftLlama.git"
        case .generationFailed(let detail):
            return "Local generation failed: \(detail)"
        }
    }
}

// MARK: - SwiftLlama Conformance
// When SwiftLlama is added as a SPM dependency, add this extension:
//
// extension SwiftLlama: StreamableLLM {
//     func stream(prompt: String, maxTokens: Int, temperature: Float) -> AsyncThrowingStream<String, Error> {
//         AsyncThrowingStream { continuation in
//             Task {
//                 do {
//                     for try await token in try await self.start(for: prompt) {
//                         continuation.yield(token)
//                     }
//                     continuation.finish()
//                 } catch {
//                     continuation.finish(throwing: error)
//                 }
//             }
//         }
//     }
// }
