"""Pure text cleanup and conservative correction acceptance rules."""
from __future__ import annotations
import difflib
import re

_PUNCT = re.compile(r"[^\w\s]", re.UNICODE)
_SPACES = re.compile(r"\s+")
_SERVICE = re.compile(r"(вот исправленн|исправленный текст|конечно[,!]|^ответ:|here is|here's|corrected text|^sure[,!]|^answer:|```|<\/?\w+>|^\s*[-*#] )",
                      re.IGNORECASE | re.MULTILINE)


def normalize(text: str) -> str:
    """Normalize case, Russian yo, punctuation and whitespace for comparison."""
    t = text.lower().replace("ё", "е").replace("%", " процентов ")
    t = re.sub(r"(\d),(\d)", r"\1.\2", t)
    t = re.sub(r"(\d)[.:](\d)", r"\1 \2", t)
    return _SPACES.sub(" ", _PUNCT.sub(" ", t)).strip()


def clean_output(text: str) -> str:
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL)
    return text.replace("<text>", "").replace("</text>", "").strip().strip('"«»').strip()


def guard(raw: str, out: str, max_len_ratio: float = 0.3, min_similarity: float = 0.6) -> tuple[bool, str]:
    """Return (accepted, rejection reason). Reject empty output, service phrases,
    markup, word-count changes above 30%, or similarity below 0.6."""
    if not out:
        return False, "empty output"
    # Service phrases are suspicious only when absent from the original speech.
    if _SERVICE.search(out) and not _SERVICE.search(raw):
        return False, "service phrases / markup"
    rw, ow = len(normalize(raw).split()), len(normalize(out).split())
    if rw and abs(ow - rw) / rw > max_len_ratio:
        return False, f"word count {ow} versus {rw}"
    sim = difflib.SequenceMatcher(None, normalize(raw), normalize(out)).ratio()
    if sim < min_similarity:
        return False, f"similarity {sim:.2f} < {min_similarity}"
    return True, ""
