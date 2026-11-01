"""Follow-up sentences that change an already-generated flow, plus dictation typos.

Real descriptions add structure after the main flow: "There is a load balancer in front of the
API." re-routes an existing edge, and "The database is multiple, round robin between them." is a
property of a box. Each function edits the example's boxes/edges and returns the sentence.
"""

import random
import re

FRONT_SENTENCES = [
    "There is a {x} in front of {y}.", "A {x} sits in front of {y}.", "Put a {x} in front of {y}.",
    "{y} is behind a {x}.", "Add a {x} before {y}.", "There's a {x} in front of {y}",
]

# Inline forms of FRONT_SENTENCES, rewritten into the sentence where {y} is first mentioned:
# "the API reads from the database, which has a cache in front of it".
INLINE_FRONT_CLAUSES = [
    "{y}, which has {x} in front of it,", "{y}, which sits behind {x},", "{y} that sits behind {x}",
    "{y} behind {x}", "{y} through {x}", "{y} via {x}", "{y}, which has {x} before it,",
]
# A clause before "..., which" would make "which" refer to the component instead of the box.
FOLLOWED_BY_WHICH = re.compile(r",?\s*which\b", re.I)
DANGLING_COMMA = re.compile(r",\s*(?=[,.;!?]|$)")

# (strategy shown in the box name, how dictation says it)
STRATEGIES = [
    ("round robin", ["uses round robin between them", "round robin across them", "with round robin"]),
    ("least connections", ["uses least connections", "balanced by least connections"]),
    ("random", ["picks one at random", "chosen randomly"]),
    ("replicated", ["are replicated", "has replicas"]),
]

REPLICA_SENTENCES = [
    "{y} is multiple and {how}.", "There are several {ys}, {how}.", "{y} has multiple instances that {how}.",
    "We run many {ys} and they {how}.", "{y} is actually a cluster, {how}",
]

TYPO_RATE = 0.06
STRATEGY_SUFFIX = re.compile(r" \([^)]*\)$")


def phrase_of(box: str, phrase_for: dict[str, str]) -> str | None:
    """How dictation refers to a box, ignoring a replication suffix: "Postgres (round robin)"."""
    return phrase_for.get(STRATEGY_SUFFIX.sub("", box))


def add_front_component(rng: random.Random, example, phrase_for: dict[str, str],
                        components: list[tuple[str, str]]) -> str | None:
    """Insert a component in front of a box: every edge into it now goes through the component."""
    targets = [target for _, target, _ in example.edges if phrase_of(target, phrase_for)]
    picked = pick_front_component(rng, example, targets, components)
    if not picked:
        return None
    target, (component, component_phrase) = picked
    route_through(example, component, target)
    sentence = rng.choice(FRONT_SENTENCES).format(x=component_phrase, y=phrase_of(target, phrase_for))
    return sentence[0].upper() + sentence[1:]


def add_inline_front_component(rng: random.Random, example, sentence: str, targets: list[str],
                               phrase_for: dict[str, str], components: list[tuple[str, str]]) -> str | None:
    """Rewrite a sentence so it puts a component in front of one of its targets, in the same clause.

    Pass only the targets of edges this sentence added, so the clause lands on an object, not a subject.
    """
    mentioned = {target: match for target in targets
                 if (match := first_mention(sentence, phrase_of(target, phrase_for)))
                 and not FOLLOWED_BY_WHICH.match(sentence, match.end())}
    picked = pick_front_component(rng, example, list(mentioned), components)
    if not picked:
        return None
    target, (component, component_phrase) = picked
    route_through(example, component, target)
    match = mentioned[target]
    clause = rng.choice(INLINE_FRONT_CLAUSES).format(x=with_article(component_phrase), y=match.group())
    return DANGLING_COMMA.sub("", sentence[:match.start()] + clause + sentence[match.end():])


def pick_front_component(rng: random.Random, example, targets: list[str],
                         components: list[tuple[str, str]]) -> tuple[str, tuple[str, str]] | None:
    candidates = [c for c in components if c[0] not in example.boxes]
    if not targets or not candidates:
        return None
    return rng.choice(targets), rng.choice(candidates)


def route_through(example, component: str, target: str) -> None:
    for edge in example.edges:
        if edge[1] == target:
            edge[1] = component
    example.boxes.insert(example.boxes.index(target), component)
    example.edges.append([component, target, "routes to"])


def first_mention(sentence: str, phrase: str | None) -> re.Match | None:
    return re.search(rf"\b{re.escape(phrase)}\b", sentence, re.I) if phrase else None


def with_article(phrase: str) -> str:
    return ("an " if phrase[0].lower() in "aeiou" else "a ") + phrase


def add_replication(rng: random.Random, example, phrase_for: dict[str, str]) -> str | None:
    """Mark a box as multiple instances: it keeps its edges and gains the strategy in its name."""
    plain_boxes = [box for box in example.boxes if box in phrase_for]
    if not plain_boxes:
        return None
    box = rng.choice(plain_boxes)
    strategy, wordings = rng.choice(STRATEGIES)
    renamed = f"{box} ({strategy})"
    example.boxes[example.boxes.index(box)] = renamed
    for edge in example.edges:
        edge[0] = renamed if edge[0] == box else edge[0]
        edge[1] = renamed if edge[1] == box else edge[1]
    phrase = phrase_for[box]
    plural = phrase.removeprefix("the ") + "s"
    sentence = rng.choice(REPLICA_SENTENCES).format(y=phrase, ys=plural, how=rng.choice(wordings))
    return sentence[0].upper() + sentence[1:]


def add_typos(rng: random.Random, text: str) -> str:
    """Dictation and fast typing produce swapped, doubled and merged letters: "tehm", "infront"."""
    words = text.split(" ")
    for index, word in enumerate(words):
        if len(word) > 3 and rng.random() < TYPO_RATE:
            words[index] = typo(rng, word)
    merged = " ".join(words)
    return merged.replace("in front", "infront") if rng.random() < 0.3 else merged


def typo(rng: random.Random, word: str) -> str:
    position = rng.randrange(1, len(word) - 2)
    kind = rng.choice(["swap", "double", "drop"])
    if kind == "swap":
        return word[:position] + word[position + 1] + word[position] + word[position + 2:]
    if kind == "double":
        return word[:position] + word[position] + word[position:]
    return word[:position] + word[position + 1:]
