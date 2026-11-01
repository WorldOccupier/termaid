"""Reword template sentences with Claude, so the model learns meaning instead of templates.

Several stories go to Claude in one request (each call has a fixed overhead), every sentence with a
randomly picked style and the diagram change it has to describe.
A rewrite only replaces its sentence when automatic checks say the diagram still matches: every
named thing is still mentioned, it is still one sentence, and conditions and else-branches neither
appear nor vanish. The target diagram never changes, so labels stay correct by construction.
"""

import random
import re
import subprocess

from claude_cli import ask_json

REWORD_RATE = 0.75

STYLES = [
    "casual spoken dictation, like someone explaining it out loud",
    "terse notes, dropping small words where it still reads naturally",
    "a formal process document",
    "reordered: state the condition or the last part first if there is one",
    "passive voice where it fits",
    "long-winded, with filler like 'basically' or 'so what happens is'",
    "a different sentence structure than the original, e.g. 'before X, Y does Z' or 'X, and then Y'",
    "plain words a non-technical person would use",
    "a quick chat message to a coworker",
    "precise, like a system design review",
]

PROMPT = """Rewrite each numbered sentence in its given style. Each one comes with the diagram change
it describes; the rewrite must describe exactly that change: the same things doing the same
actions in the same direction, and the same conditions with the same yes/no outcomes. Keep every
phrase listed under "keep" word for word, and keep each action's main verb (its form may change,
e.g. "forwards it to" -> "forwarding it on to"). Vary everything else: sentence structure, word
order, clause order, tone, filler. Don't add steps, things or conditions, and keep each rewrite to
one sentence.
Reply with JSON: {{"rewrites": ["<rewrite of 1>", "<rewrite of 2>", ...]}}

{numbered}"""


CONDITION_WORDS = re.compile(r"\b(if|when|whenever|unless|only|otherwise|else|falling back|fall back|falls back|on a|on an|in case|once|as long as|whether)\b", re.I)
ELSE_WORDS = re.compile(r"\b(otherwise|else|instead|if not|falling back|fall back|falls back|or)\b", re.I)


def phrases_to_keep(sentence: str, phrases: list[str]) -> list[str]:
    """Named things the sentence mentions, without a leading 'the' so 'a recruiter' still counts."""
    lowered = sentence.lower()
    found = {p.removeprefix("the ") for p in phrases if p.removeprefix("the ").lower() in lowered}
    # Drop phrases contained in a longer found one: "server" inside "origin server".
    return sorted(p for p in found if not any(p != q and p.lower() in q.lower() for q in found))


def keeps_meaning(original: str, rewrite, keep: list[str], split_sentences) -> bool:
    if not isinstance(rewrite, str) or not rewrite.strip() or rewrite.strip().lower() == original.lower():
        return False
    if len(split_sentences(rewrite)) != 1 or not 0.5 <= len(rewrite) / len(original) <= 2.5:
        return False
    if not all(p.lower() in rewrite.lower() for p in keep):
        return False
    had_condition, has_condition = bool(CONDITION_WORDS.search(original)), bool(CONDITION_WORDS.search(rewrite))
    had_else = bool(re.search(r"\b(otherwise|else|falling back)\b", original, re.I))
    return had_condition == has_condition and (not had_else or bool(ELSE_WORDS.search(rewrite)))


def describe_change(before: dict, after: dict) -> str:
    def arrow(edge):
        return f"{edge[0]} -{edge[2] or ''}-> {edge[1]}"
    added = [arrow(e) for e in after["edges"] if e not in before["edges"]]
    removed = [arrow(e) for e in before["edges"] if e not in after["edges"]]
    return "; ".join([f"adds {', '.join(added)}"] + ([f"removes {', '.join(removed)}"] if removed else []))


def reword_stories(rng: random.Random, stories: list[tuple[list[tuple[dict, str, dict]], list[str]]],
                   split_sentences) -> list[list[str]]:
    """Takes (steps, phrases) per story; returns each story's sentences with checked rewrites swapped in.

    A sentence whose rewrite fails the checks keeps its template wording, and a failed call keeps all of them.
    """
    items = [(sentence, phrases_to_keep(sentence, phrases), describe_change(before, after))
             for steps, phrases in stories for before, sentence, after in steps]
    originals = [sentence for sentence, _, _ in items]
    numbered = "\n".join(f'{i + 1}. "{s}"\n   diagram change: {change}\n   style: {rng.choice(STYLES)}\n'
                         f'   keep: {", ".join(k) or "-"}' for i, (s, k, change) in enumerate(items))
    try:
        reply = ask_json(PROMPT.format(numbered=numbered))
    except (OSError, subprocess.TimeoutExpired):
        reply = None
    rewrites = reply.get("rewrites") if isinstance(reply, dict) else None
    if isinstance(rewrites, list) and len(rewrites) == len(items):
        sentences = [rewrite.strip() if rng.random() < REWORD_RATE and keeps_meaning(s, rewrite, k, split_sentences)
                     else s for (s, k, _), rewrite in zip(items, rewrites)]
    else:
        sentences = originals
    grouped, start = [], 0
    for steps, _ in stories:
        grouped.append(sentences[start:start + len(steps)])
        start += len(steps)
    return grouped
