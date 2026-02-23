"""
Tests for backend/prompts.py — mode detection, prompt building, outline→essay flow.
"""
import pytest
from backend.prompts import (
    detect_mode_command,
    strip_outline_trigger,
    strip_mbe_trigger,
    build_prompt,
    build_essay_from_outline_prompt,
)


# ======================================================================
# Mode detection
# ======================================================================

class TestModeDetection:

    @pytest.mark.parametrize("text,expected", [
        ("next question", "reset"),
        ("Next Question", "reset"),
        ("new prompt", "reset"),
        ("start over", "reset"),
        ("startover", "reset"),
        ("start over!", "reset"),
    ])
    def test_reset_commands(self, text, expected):
        assert detect_mode_command(text) == expected

    @pytest.mark.parametrize("text,expected", [
        ("outline only contracts question", "outline"),
        ("What are torts? outline only", "outline"),
        ("Give me an OUTLINE ONLY for evidence", "outline"),
    ])
    def test_outline_commands(self, text, expected):
        assert detect_mode_command(text) == expected

    @pytest.mark.parametrize("text,expected", [
        ("yes", "yes"),
        ("Yeah", "yes"),
        ("sure", "yes"),
        ("go ahead", "yes"),
        ("ok", "yes"),
        ("affirmative", "yes"),
        ("do it", "yes"),
    ])
    def test_yes_commands(self, text, expected):
        assert detect_mode_command(text) == expected

    @pytest.mark.parametrize("text,expected", [
        ("exam mode what is negligence", "mbe"),
        ("question mode explain the UCC", "mbe"),
        ("What is torts? exam mode", "mbe"),
        ("EXAM MODE contracts question", "mbe"),
    ])
    def test_mbe_commands(self, text, expected):
        assert detect_mode_command(text) == expected

    @pytest.mark.parametrize("text,expected", [
        ("What is negligence?", "question"),
        ("Explain the UCC", "question"),
        ("How does community property work in California?", "question"),
        ("", "question"),
    ])
    def test_normal_questions(self, text, expected):
        assert detect_mode_command(text) == expected


class TestStripOutlineTrigger:

    def test_strips_outline_only(self):
        result = strip_outline_trigger("outline only contracts question")
        assert "outline only" not in result.lower()
        assert "contracts" in result

    def test_preserves_question(self):
        original = "What are the elements of negligence?"
        assert strip_outline_trigger(original) == original


class TestStripMbeTrigger:

    def test_strips_exam_mode(self):
        result = strip_mbe_trigger("exam mode what is negligence")
        assert "exam mode" not in result.lower()
        assert "negligence" in result

    def test_strips_question_mode(self):
        result = strip_mbe_trigger("question mode explain UCC")
        assert "question mode" not in result.lower()
        assert "UCC" in result

    def test_preserves_question(self):
        original = "What are the elements of negligence?"
        assert strip_mbe_trigger(original) == original


# ======================================================================
# Prompt builders
# ======================================================================

class TestBuildPrompt:

    def test_returns_list_of_dicts(self):
        msgs = build_prompt("What is negligence?")
        assert isinstance(msgs, list)
        assert all(isinstance(m, dict) for m in msgs)
        assert all("role" in m and "content" in m for m in msgs)

    def test_system_prompt_present(self):
        msgs = build_prompt("Q?")
        system_msgs = [m for m in msgs if m["role"] == "system"]
        assert len(system_msgs) >= 1

    def test_user_question_present(self):
        msgs = build_prompt("What is strict liability?")
        user_msgs = [m for m in msgs if m["role"] == "user"]
        assert len(user_msgs) == 1
        assert "strict liability" in user_msgs[0]["content"]

    def test_essay_mode_contains_irac(self):
        msgs = build_prompt("Q?", mode="essay")
        system_text = " ".join(m["content"] for m in msgs if m["role"] == "system")
        assert "IRAC" in system_text

    def test_outline_mode_contains_outline(self):
        msgs = build_prompt("Q?", mode="outline")
        system_text = " ".join(m["content"] for m in msgs if m["role"] == "system")
        assert "OUTLINE" in system_text.upper()

    def test_mbe_mode_contains_concise(self):
        msgs = build_prompt("Q?", mode="mbe")
        system_text = " ".join(m["content"] for m in msgs if m["role"] == "system")
        assert "MBE" in system_text.upper()
        assert "NEVER write an essay" in system_text
        assert "SECTION_BREAK" not in system_text

    def test_rag_context_injected(self):
        msgs = build_prompt("Q?", rag_context="Test RAG context here")
        all_text = " ".join(m["content"] for m in msgs)
        assert "Test RAG context here" in all_text

    def test_no_rag_context(self):
        msgs = build_prompt("Q?", rag_context="")
        # Should have system + user = 2 messages, no extra context msg
        assert len(msgs) == 2

    def test_section_break_marker_in_system(self):
        msgs = build_prompt("Q?", mode="essay")
        system_text = " ".join(m["content"] for m in msgs if m["role"] == "system")
        assert "SECTION_BREAK" in system_text

    def test_tts_pacing_in_system(self):
        msgs = build_prompt("Q?", mode="essay")
        system_text = " ".join(m["content"] for m in msgs if m["role"] == "system")
        assert "80 words per minute" in system_text


class TestBuildEssayFromOutlinePrompt:

    def test_includes_outline(self):
        msgs = build_essay_from_outline_prompt(
            original_question="What is negligence?",
            outline_text="I. Duty\nII. Breach",
        )
        all_text = " ".join(m["content"] for m in msgs)
        assert "Duty" in all_text
        assert "Breach" in all_text

    def test_includes_original_question(self):
        msgs = build_essay_from_outline_prompt(
            original_question="Analyze strict liability",
            outline_text="outline",
        )
        user_msgs = [m for m in msgs if m["role"] == "user"]
        assert any("strict liability" in m["content"].lower() for m in user_msgs)

    def test_rag_context_optional(self):
        msgs = build_essay_from_outline_prompt("Q", "outline", rag_context="RAG bits")
        all_text = " ".join(m["content"] for m in msgs)
        assert "RAG bits" in all_text
