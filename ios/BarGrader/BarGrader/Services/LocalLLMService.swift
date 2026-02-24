import Foundation
import LLM

/// On-device LLM inference via **LLM.swift** (llama.cpp under the hood).
///
/// Provides **offline fallback** when the BarGrader server is unreachable.
/// Loads a small quantised GGUF model bundled with the app (or auto-downloads
/// from HuggingFace on first launch) and streams tokens back.
///
/// Quality is intentionally lower than the server (GPT-4o / Gemini) — this
/// is "better than nothing" mode for flights, courthouses, etc.
///
/// ## Model Requirements
/// - Format: GGUF (Q4_K_M quantisation recommended)
/// - Size: ≤ 1.2 GB to fit comfortably on iPhone RAM
/// - Default: SmolLM2-1.7B-Instruct-Q4_K_M (auto-downloaded if not bundled)
@MainActor
final class LocalLLMService: ObservableObject {
    static let shared = LocalLLMService()

    // MARK: - Published State
    @Published var isModelLoaded = false
    @Published var isGenerating  = false
    @Published var loadError: String?
    @Published var downloadProgress: Double = 0   // 0…1

    // MARK: - Configuration
    static let bundledModelName = "bargrader-model.gguf"

    /// Reference to the loaded LLM.swift model.
    private var bot: LLM?

    private init() {}

    // MARK: - Bar Exam System Prompt (baked in — no RAG needed offline)

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

    // MARK: - Model Loading

    /// Attempt to load the GGUF model. Checks bundle first, then auto-downloads.
    /// Call once at app startup. Non-blocking.
    func preloadModel() {
        guard !isModelLoaded else { return }

        // 1. Try bundled / Documents-directory model first
        if let localURL = localModelURL() {
            print("[LocalLLM] Loading bundled model: \(localURL.lastPathComponent)")
            loadFromURL(localURL)
            return
        }

        // 2. Auto-download from HuggingFace
        print("[LocalLLM] No bundled model — downloading from HuggingFace...")
        downloadFromHuggingFace()
    }

    /// Load from a local file URL.
    private func loadFromURL(_ url: URL) {
        Task.detached(priority: .utility) { [weak self] in
            let llm = LLM(from: url, template: .chatML(Self.barExamSystemPrompt))
            await MainActor.run {
                self?.bot = llm
                self?.isModelLoaded = true
                self?.loadError = nil
                print("[LocalLLM] Model loaded successfully")
            }
        }
    }

    /// Download model from HuggingFace with progress tracking.
    private func downloadFromHuggingFace() {
        let hfModel = HuggingFaceModel(
            "bartowski/SmolLM2-1.7B-Instruct-GGUF",
            .Q4_K_M,
            template: .chatML(Self.barExamSystemPrompt)
        )

        Task.detached(priority: .utility) { [weak self] in
            let llm = await LLM(from: hfModel) { progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }
            await MainActor.run {
                if let llm = llm {
                    self?.bot = llm
                    self?.isModelLoaded = true
                    self?.loadError = nil
                    self?.downloadProgress = 1.0
                    print("[LocalLLM] HuggingFace model downloaded and loaded")
                } else {
                    self?.loadError = "Failed to initialize model from HuggingFace"
                    print("[LocalLLM] \(self?.loadError ?? "")")
                }
            }
        }
    }

    /// Locate the .gguf file — Documents first, then app bundle.
    private func localModelURL() -> URL? {
        // 1. Documents directory (user-supplied / previously downloaded)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let docsModel = docs.appendingPathComponent(Self.bundledModelName)
        if FileManager.default.fileExists(atPath: docsModel.path) {
            return docsModel
        }

        // 2. App bundle (compiled into the .ipa via Xcode)
        if let bundled = Bundle.main.url(
            forResource: Self.bundledModelName.replacingOccurrences(of: ".gguf", with: ""),
            withExtension: "gguf"
        ) {
            return bundled
        }

        return nil
    }

    // MARK: - Inference (Streaming)

    /// Stream tokens for a given question using the on-device model.
    func stream(question: String, mode: String = "essay") -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard let bot = self.bot, isModelLoaded else {
                continuation.finish(throwing: LocalLLMError.modelNotLoaded)
                return
            }

            Task.detached(priority: .userInitiated) { [weak self] in
                await MainActor.run { self?.isGenerating = true }

                let modeInstruction = Self.modeInstruction(for: mode)
                let input = "\(modeInstruction)\n\n\(question)"

                // Use LLM.swift's respond with custom output handler for streaming
                await bot.respond(to: input) { stream in
                    var full = ""
                    for await delta in stream {
                        full += delta
                        continuation.yield(delta)
                    }
                    continuation.finish()
                    return full
                }

                await MainActor.run { self?.isGenerating = false }
            }
        }
    }

    /// Mode-specific instruction prefix.
    private static func modeInstruction(for mode: String) -> String {
        switch mode {
        case "mbe":
            return "[MBE MODE] Answer with the letter first, then a 1-2 sentence explanation."
        case "outline":
            return "[OUTLINE MODE] Bullet-point the issues with brief rule statements. No full essay."
        default:
            return "[ESSAY MODE] Use IRAC format: Issue, Rule, Application, Conclusion."
        }
    }
}

// MARK: - Errors

enum LocalLLMError: LocalizedError {
    case modelNotLoaded
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Local model not loaded. Wait for download or add bargrader-model.gguf to bundle."
        case .generationFailed(let detail):
            return "Local generation failed: \(detail)"
        }
    }
}
