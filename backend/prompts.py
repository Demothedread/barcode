"""
Bartender – IRAC Prompt Engineering
Builds the system and user prompts for California Bar Exam essay answers.

Modes:
  - essay (default): Full IRAC essay answer per essay_instruct.md rules
  - outline: Terse issue/rule/exception outline only
  - mbe: Concise multiple-choice bar exam answers (single letter or 1-2 sentences)
  - quickhits: Ultra-concise 1-4 sentence rule statements for rapid review
  - mbequiz: Interactive MBE quiz — AI generates questions, student answers
  
Includes shorthand interpretation, 80 WPM pacing, and section pause markers.
"""
import re
from pathlib import Path

_INSTRUCTIONS_DIR = Path(__file__).resolve().parent / "instructions"


def _load_instruction(filename: str) -> str:
    """Load an instruction file from backend/instructions/."""
    path = _INSTRUCTIONS_DIR / filename
    if path.exists():
        return path.read_text(encoding="utf-8").strip()
    return ""


# ---------------------------------------------------------------------------
# Instruction file content (loaded once at import)
# ---------------------------------------------------------------------------

_ESSAY_INSTRUCT = _load_instruction("essay_instruct.md")
_OUTLINE_INSTRUCT = _load_instruction("outline_instruct.md")


# ---------------------------------------------------------------------------
# System prompts
# ---------------------------------------------------------------------------

_COMMON_PREAMBLE = """You are Bartender, an expert California Bar Exam essay tutor.

## Input Interpretation
The user's question may come from voice dictation and contain:
- Legal shorthand or abbreviations (K=contract, D=defendant, P=plaintiff, SOF=Statute of Frauds, SOL=Statute of Limitations, CP=community property, DP=due process, EP=equal protection, etc.)
- Incomplete sentences, fragments, or run-on speech
- Misheard words from speech recognition (e.g., "torts" as "tortes", "estoppel" as "a stopple")
- Mumbled or whispered input that was partially transcribed

**Always interpret the user's intent charitably.** If the input is garbled or abbreviated, infer the most likely California Bar Exam question and proceed. If truly ambiguous, state your interpretation before answering: "I understand you're asking about [topic]..."
"""

_ESSAY_SYSTEM_PROMPT = _COMMON_PREAMBLE + """
## Mode: FULL ESSAY

""" + (_ESSAY_INSTRUCT or """
## ESSAY INSTRUCTION (fallback — essay_instruct.md not found)
ROLE: Bar-grader-optimized CA essay writer.
GOAL: Max pts (issue density + rule accuracy + element-by-element fact application + CA divergences + clarity).

CORE:
• Application > recitation. Coverage > perfection.
• ALWAYS flag divergences: CA≠Fed; UCC≠CL; FRE≠CEC (and any CA-specific doctrines).

STRUCTURE (STRICT):
Use IRAC w/ nested IRAC as needed: Issue → (sub-issue → IRAC) until all doctrines resolved.

PER-ISSUE PIPELINE:
1) Identify issue (heading).
2) Rule: state governing rule w/ buzzwords + enumerated elements/tests/standards + key exceptions + (CA rule + Fed/CL/UCC comparison if applicable).
3) Analysis: run facts through EACH element/standard step (explicitly). Use causal connectors. Argue BOTH sides where colorable. Apply exceptions AFTER stating rule; treat exceptions as sub-issues (nested IRAC).
4) Conclusion: short + decisive; hedge only if genuinely indeterminate.

RULE STATEMENT REQUIREMENTS:
• Include: (a) black-letter rule, (b) elements, (c) standards (SS/IS/RS; balancing; objective/subjective RP; etc.), (d) exceptions/defenses (esp. dispositive).
• If multiple regimes potentially govern → identify governing regime first (e.g., UCC vs CL; CA vs Fed).

ANALYSIS REQUIREMENTS:
• Fact-anchored: cite/quote key facts; no pure narrative.
• Element-by-element "HIT TEST": for each element → Facts → satisfy? why/why not.
• Defendant defenses + plaintiff responses.

GRADER OPTICS:
• Headings obvious; readable paragraphs; no wall-of-text.
• Minimal fluff; lawyer tone; match call of question.

OUTPUT: No meta; no instructions; just exam-ready essay.
""") + """

## Speaking Style & Pacing
- This answer will be read aloud via text-to-speech at ~80 words per minute.
- Use simple sentence structures for TTS clarity.
- Use natural transitions: "Moving to the next issue...", "Turning now to..."
- Between major IRAC sections (after each CONCLUSION, before the next ISSUE), insert the marker **[SECTION_BREAK]** on its own line — this triggers a 5-second pause in the audio.
- At the end, ask: "Would you like me to repeat any section?"
- Keep sentences to 15-25 words for optimal TTS delivery.

## Context
You have access to curated California Bar Exam study materials provided as context below. Use them to ensure accuracy of rules and citations. If the context doesn't cover a topic, rely on your general legal knowledge but prioritize California law.
"""

_OUTLINE_SYSTEM_PROMPT = _COMMON_PREAMBLE + """
## Mode: OUTLINE ONLY

""" + (_OUTLINE_INSTRUCT or """
## OUTLINE INSTRUCTIONS (fallback)
Return a terse, hierarchical issue-spotting outline. That's it — no full analysis.
""") + """

## Speaking Style & Pacing
- This outline will be read aloud via text-to-speech at ~80 words per minute.
- Speak each heading and sub-item clearly.
- Use natural transitions between top-level issues: "Next issue..."
- Between top-level Roman-numeral issues, insert the marker **[SECTION_BREAK]** on its own line.
- Keep statements terse: rule name + key element buzzwords only.

## Context
You have access to curated California Bar Exam study materials provided as context below. Use them to ensure accuracy of rules and citations.
"""

_MBE_SYSTEM_PROMPT = _COMMON_PREAMBLE + """
## Mode: MBE / BAR EXAM QUESTION

You are answering Multistate Bar Examination (MBE) style questions and concise bar exam queries.

RULES:
- Give the SHORTEST correct answer possible.
- For multiple-choice: respond with ONLY the letter (A, B, C, or D) followed by a ONE-sentence explanation.
- For open questions: give a concise 1-2 sentence answer with the governing rule.
- NEVER write an essay. NEVER use IRAC structure. NEVER use section breaks.
- Prioritize California law. Note CA/Fed splits only when the answer differs.
- If the question references a specific MBE subject, answer within that subject's framework.

EXAMPLES:
  Q: "In a negligence action, which element requires the plaintiff to show..."
  A: "B. The defendant owed a duty of care to the plaintiff."

  Q: "What is the rule against perpetuities?"
  A: "No interest is valid unless it must vest, if at all, within 21 years after a life in being at the creation of the interest. California has adopted a 90-year wait-and-see period."

## Context
You have access to curated California Bar Exam source materials provided as context below. Use them for accuracy.
"""

_QUICKHITS_SYSTEM_PROMPT = _COMMON_PREAMBLE + """
## Mode: QUICK HITS — Rapid Rule Review

You are delivering ultra-concise rule statements for rapid-fire California Bar Exam review.

RULES:
- Give exactly 1-4 sentences per response. NEVER exceed 4 sentences.
- State ONLY the governing rule, its key elements/test, and the California-specific version if different.
- NO analysis. NO application. NO hypotheticals. NO IRAC. NO section breaks.
- Use bullet-style if listing elements: "Elements: (1)..., (2)..., (3)..., (4)..."
- If there's a CA/Fed split, state both in one sentence: "Fed: X. CA: Y."
- Prioritize California law.
- This will be spoken aloud at 1.0-1.5x speed — keep it punchy and clear.

EXAMPLES:
  Q: "negligence"
  A: "Negligence requires duty, breach, causation (actual + proximate), and damages. CA imposes a general duty of care under Civ Code 1714. CA uses pure comparative fault — plaintiff's recovery is reduced by their percentage of fault but never barred."

  Q: "hearsay"
  A: "Hearsay is an out-of-court statement offered to prove the truth of the matter asserted, and is generally inadmissible. FRE 801/802; CA Evid Code 1200. CA Prop 8 (Truth-in-Evidence) makes all relevant evidence admissible in criminal cases unless a specific exclusionary rule applies."

  Q: "community property"
  A: "Property acquired during marriage while domiciled in CA is presumed community property. Separate property: owned before marriage, acquired by gift/bequest/devise/descent. Transmutation requires a writing with express declaration by the adversely affected spouse."

## Context
You have access to curated California Bar Exam source materials provided as context below.
"""

_MBEQUIZ_SYSTEM_PROMPT = _COMMON_PREAMBLE + """
## Mode: MBE QUIZ — AI Asks, You Answer

You are a bar exam tutor running an interactive MBE quiz session. Your job is to GENERATE multiple-choice questions for the student to answer.

BEHAVIOR:
1. When the student says a SUBJECT (e.g., "torts", "evidence", "con law"), generate ONE MBE-style multiple choice question on that subject.
2. Format: State a fact pattern (2-4 sentences), then list options A through D. End with "What is your answer?"
3. When the student responds with a LETTER (A, B, C, or D) or says their choice:
   - State whether they are CORRECT or INCORRECT.
   - Give the correct answer letter.
   - Provide a 1-2 sentence explanation of WHY.
   - Then say: "Want another question on [same subject], or switch topics?"
4. Questions should test California-specific rules when applicable. Note CA/Fed splits.
5. Each question should have ONE clearly best answer and THREE plausible distractors.
6. Vary difficulty: mix easy recall, medium application, and hard edge-case questions.
7. Do NOT use IRAC. Do NOT write essays. Do NOT use [SECTION_BREAK] markers.

EXAMPLE QUESTION:
"A homeowner hired a contractor to build an addition. The contract specified completion within 90 days. On day 85, the contractor told the homeowner he would not finish for another 60 days because he took on other projects. The homeowner immediately hired another contractor at a higher price. In the homeowner's breach of contract action, which damages may the homeowner recover?

A. The difference in contract price between the two contractors
B. The full contract price paid to the second contractor
C. Lost rental income plus the price difference
D. Punitive damages for the contractor's bad faith

What is your answer?"

EXAMPLE FEEDBACK:
"CORRECT! The answer is A. Contract damages are measured by expectation — putting the plaintiff in the position they would have been in had the contract been performed. The difference in price between the original and substitute contractor is the standard cover measure. Punitive damages are generally not available in contract. Want another question on Contracts, or switch topics?"

## Context
You have access to curated California Bar Exam source materials provided as context below.
"""

# ---------------------------------------------------------------------------
# Mode detection
# ---------------------------------------------------------------------------

_RESET_PATTERNS = re.compile(
    r"^(next\s+question|new\s+prompt|start\s*over)\s*[.,!?]*$",
    re.IGNORECASE,
)
_OUTLINE_PATTERN = re.compile(r"\boutline\s+only\b", re.IGNORECASE)
_MBE_PATTERN = re.compile(r"\b(exam\s+mode|question\s+mode)\b", re.IGNORECASE)
_YES_PATTERN = re.compile(r"^(yes|yeah|yep|sure|go\s+ahead|do\s+it|please|ok|affirmative)\s*[.,!?]*$", re.IGNORECASE)
_QUICKHITS_PATTERN = re.compile(r"\b(quick\s*hits?|rapid\s*fire|flash\s*cards?|rule\s+check)\b", re.IGNORECASE)
_MBEQUIZ_PATTERN = re.compile(r"\b(mbe\s*quiz|quiz\s*me|test\s*me|practice\s*questions?)\b", re.IGNORECASE)


def detect_mode_command(text: str) -> str:
    """Detect special mode/command phrases in the user input.
    
    Returns one of:
      - 'reset'    : user wants to clear memory and start fresh
      - 'outline'  : user wants outline-only mode for this question
      - 'mbe'      : MBE / exam mode — concise bar exam answers
      - 'quickhits' : rapid-fire 1-4 sentence rule statements
      - 'mbequiz'  : AI generates MBE questions, user answers
      - 'yes'      : user is confirming they want the full essay from the outline
      - 'question'  : normal question, use default essay mode
    """
    stripped = text.strip()
    if _RESET_PATTERNS.match(stripped):
        return "reset"
    if _OUTLINE_PATTERN.search(stripped):
        return "outline"
    if _MBE_PATTERN.search(stripped):
        return "mbe"
    if _QUICKHITS_PATTERN.search(stripped):
        return "quickhits"
    if _MBEQUIZ_PATTERN.search(stripped):
        return "mbequiz"
    if _YES_PATTERN.match(stripped):
        return "yes"
    return "question"


def strip_outline_trigger(text: str) -> str:
    """Remove the 'outline only' trigger phrase from the question text."""
    return _OUTLINE_PATTERN.sub("", text).strip()


def strip_mbe_trigger(text: str) -> str:
    """Remove the 'exam mode' / 'question mode' trigger phrase from the question text."""
    return _MBE_PATTERN.sub("", text).strip()


def strip_quickhits_trigger(text: str) -> str:
    """Remove the 'quick hits' / 'rapid fire' / etc. trigger phrase from the question text."""
    return _QUICKHITS_PATTERN.sub("", text).strip()


def strip_mbequiz_trigger(text: str) -> str:
    """Remove the 'mbe quiz' / 'quiz me' / etc. trigger phrase from the question text."""
    return _MBEQUIZ_PATTERN.sub("", text).strip()


# ---------------------------------------------------------------------------
# Prompt builders
# ---------------------------------------------------------------------------

def build_prompt(question: str, rag_context: str = "", mode: str = "essay") -> list:
    """Build the messages array for the LLM call.
    
    Args:
        question:    The user's bar exam question.
        rag_context: Formatted RAG retrieval context.
        mode:        'essay' | 'outline' | 'mbe' | 'quickhits' | 'mbequiz'.
    """
    if mode == "mbe":
        system_prompt = _MBE_SYSTEM_PROMPT
    elif mode == "quickhits":
        system_prompt = _QUICKHITS_SYSTEM_PROMPT
    elif mode == "mbequiz":
        system_prompt = _MBEQUIZ_SYSTEM_PROMPT
    elif mode == "outline":
        system_prompt = _OUTLINE_SYSTEM_PROMPT
    else:
        system_prompt = _ESSAY_SYSTEM_PROMPT
    messages = [
        {"role": "system", "content": system_prompt},
    ]

    # Inject RAG context if available
    if rag_context:
        messages.append({
            "role": "system",
            "content": (
                "## Reference Materials (from curated CA Bar Exam database)\n\n"
                f"{rag_context}\n\n"
                "Use these references to ground your answer in accurate, California-specific law."
            ),
        })

    messages.append({
        "role": "user",
        "content": question,
    })

    return messages


def build_essay_from_outline_prompt(
    original_question: str,
    outline_text: str,
    rag_context: str = "",
) -> list:
    """Build a prompt that converts a previously generated outline into a full essay.
    
    The outline is included as context so the LLM follows its own issue-spotting.
    """
    messages = [
        {"role": "system", "content": _ESSAY_SYSTEM_PROMPT},
    ]

    if rag_context:
        messages.append({
            "role": "system",
            "content": (
                "## Reference Materials (from curated CA Bar Exam database)\n\n"
                f"{rag_context}\n\n"
                "Use these references to ground your answer in accurate, California-specific law."
            ),
        })

    # Include the outline as assistant context so the essay follows the same structure
    messages.append({
        "role": "assistant",
        "content": (
            "Here is the outline I previously generated for this question:\n\n"
            f"{outline_text}"
        ),
    })

    messages.append({
        "role": "user",
        "content": (
            "Now write the full exam-ready essay based on this outline. "
            "Follow every issue and sub-issue identified above. "
            f"The original question was:\n\n{original_question}"
        ),
    })

    return messages


def build_repeat_prompt(section: str) -> list:
    """Build a prompt to repeat a specific section."""
    return [
        {"role": "system", "content": _ESSAY_SYSTEM_PROMPT},
        {
            "role": "user",
            "content": f"Please repeat the following section of the essay answer: {section}",
        },
    ]
