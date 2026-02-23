"""
BarGrader – IRAC Prompt Engineering
Builds the system and user prompts for California Bar Exam essay answers.

Modes:
  - essay (default): Full IRAC essay answer per essay_instruct.md rules
  - outline: Terse issue/rule/exception outline only
  - mbe: Concise multiple-choice bar exam answers (single letter or 1-2 sentences)
  
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

_COMMON_PREAMBLE = """You are BarGrader, an expert California Bar Exam essay tutor.

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


def detect_mode_command(text: str) -> str:
    """Detect special mode/command phrases in the user input.
    
    Returns one of:
      - 'reset'   : user wants to clear memory and start fresh
      - 'outline' : user wants outline-only mode for this question
      - 'mbe'     : MBE / exam mode — concise bar exam answers
      - 'yes'     : user is confirming they want the full essay from the outline
      - 'question': normal question, use default essay mode
    """
    stripped = text.strip()
    if _RESET_PATTERNS.match(stripped):
        return "reset"
    if _OUTLINE_PATTERN.search(stripped):
        return "outline"
    if _MBE_PATTERN.search(stripped):
        return "mbe"
    if _YES_PATTERN.match(stripped):
        return "yes"
    return "question"


def strip_outline_trigger(text: str) -> str:
    """Remove the 'outline only' trigger phrase from the question text."""
    return _OUTLINE_PATTERN.sub("", text).strip()


def strip_mbe_trigger(text: str) -> str:
    """Remove the 'exam mode' / 'question mode' trigger phrase from the question text."""
    return _MBE_PATTERN.sub("", text).strip()


# ---------------------------------------------------------------------------
# Prompt builders
# ---------------------------------------------------------------------------

def build_prompt(question: str, rag_context: str = "", mode: str = "essay") -> list:
    """Build the messages array for the LLM call.
    
    Args:
        question:    The user's bar exam question.
        rag_context: Formatted RAG retrieval context.
        mode:        'essay' | 'outline' | 'mbe'.
    """
    if mode == "mbe":
        system_prompt = _MBE_SYSTEM_PROMPT
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
