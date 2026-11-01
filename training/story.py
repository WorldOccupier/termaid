"""Multi-sentence descriptions as training steps: (diagram before, sentence) -> diagram after.

termaid sends the model one sentence at a time with the diagram so far, so every training
example is one such step. A story picks a domain, starts with a first flow sentence and adds
follow-ups that extend, branch, loop back, re-route or annotate it. Complex stories chain many
follow-ups, so later steps carry large diagrams with several decisions.
"""

import copy
import json
import random
import re
from dataclasses import dataclass

from domains import DOMAIN_WEIGHTS, DOMAINS, Domain
from follow_ups import (STRATEGY_SUFFIX, add_front_component, add_inline_front_component, add_replication,
                        add_typos, phrase_of)
from generate_data import Example, capitalize, conditional_step, make_example, plain_step

# Keep in sync with SENTENCE_BREAK in src/sentences.ts.
SENTENCE_BREAK = re.compile(r"(?<=[.!?])\s+|\n+")
COMPLEX_STORY_RATE = 0.3
SIMPLE_FOLLOW_UPS = (0, 3)
COMPLEX_FOLLOW_UPS = (4, 7)
TYPO_SENTENCE_RATE = 0.2
# Standalone "There is a cache in front of the database." follow-ups are about 8% of steps; match it inline.
INLINE_FRONT_RATE = 0.15

LOOP_BACK_SENTENCES = [
    "If {condition}, {source} sends it back to {target}.",
    "{source_cap} returns it to {target} when {condition}.",
    "When {condition} {source} goes back to {target}.",
    "If {condition} then {source} loops back to {target}.",
]


@dataclass(frozen=True)
class StoryContext:
    domain: Domain
    phrase_for: dict[str, str]


def split_sentences(text: str) -> list[str]:
    return [sentence.strip() for sentence in SENTENCE_BREAK.split(text) if sentence.strip()]


def snapshot(example: Example) -> dict:
    return {"direction": "LR", "boxes": list(example.boxes), "edges": copy.deepcopy(example.edges)}


# Keep in sync with formatUpdateRequest in src/diagramState.ts: compact JSON, same key order.
def format_update_request(state: dict, sentence: str) -> str:
    compact = json.dumps(state, separators=(",", ":"), ensure_ascii=False)
    return f"Diagram so far: {compact}\nNext sentence: {sentence}"


def new_things(rng: random.Random, context: StoryContext, example: Example, count: int) -> list[tuple[str, str]] | None:
    taken = {STRATEGY_SUFFIX.sub("", box) for box in example.boxes}
    unused = [thing for thing in context.domain.things if thing[0] not in taken]
    return rng.sample(unused, count) if len(unused) >= count else None


def existing_things(context: StoryContext, example: Example) -> list[tuple[str, str]]:
    return [(box, phrase_of(box, context.phrase_for)) for box in example.boxes if phrase_of(box, context.phrase_for)]


def branch_from_existing(rng: random.Random, context: StoryContext, example: Example) -> str | None:
    """'If the payment fails the order service emails support, else it publishes to kafka.'"""
    known, fresh = existing_things(context, example), new_things(rng, context, example, 2)
    if not known or not fresh:
        return None
    source = rng.choice(known)
    if rng.random() < 0.3:
        return capitalize(plain_step(rng, context.domain, example, source, fresh[0])) + "."
    return capitalize(conditional_step(rng, context.domain, example, source, fresh[0], fresh[1])) + "."


def new_flow_joining(rng: random.Random, context: StoryContext, example: Example) -> str | None:
    """'The worker pulls from kafka and writes to postgres, falling back to s3 when postgres is down.'"""
    known, fresh = existing_things(context, example), new_things(rng, context, example, 3)
    if not known or not fresh:
        return None
    subject, target, other = fresh
    text = plain_step(rng, context.domain, example, subject, rng.choice(known))
    if rng.random() < 0.6:
        conditional = rng.random() < 0.6
        follow = (conditional_step(rng, context.domain, example, subject, target, other) if conditional
                  else plain_step(rng, context.domain, example, subject, target))
        text += " and" + follow[len(subject[1]):] if follow.startswith(subject[1]) else ", and " + follow
    return capitalize(text) + "."


def loop_back(rng: random.Random, context: StoryContext, example: Example) -> str | None:
    """'If the panel rejects, the hiring manager sends it back to the recruiter.' Edges to an earlier box."""
    known = existing_things(context, example)
    if len(known) < 2:
        return None
    source, target = rng.sample(known, 2)
    question, wordings = rng.choice(context.domain.conditions)
    example.edge(source[0], question, "")
    example.edge(question, target[0], "yes")
    template = rng.choice(LOOP_BACK_SENTENCES)
    return capitalize(template.format(condition=rng.choice(wordings), source=source[1],
                                      source_cap=capitalize(source[1]), target=target[1]))


def front_component(rng: random.Random, context: StoryContext, example: Example) -> str | None:
    return add_front_component(rng, example, context.phrase_for, context.domain.front_components)


def replication(rng: random.Random, context: StoryContext, example: Example) -> str | None:
    return add_replication(rng, example, context.phrase_for) if context.domain.replicable else None


FOLLOW_UPS = [front_component, replication, branch_from_existing, branch_from_existing, new_flow_joining, loop_back]


def make_story(rng: random.Random) -> tuple[list[tuple[dict, str, dict]], list[str]]:
    """Steps with template sentences, plus the phrases a rewrite must keep; add_story_typos runs after any rewording."""
    domain = rng.choices(DOMAINS, weights=DOMAIN_WEIGHTS)[0]
    context = StoryContext(domain, dict(domain.things))
    example = make_example(rng, domain)
    first_sentence = maybe_inline_front(rng, context, example, example.text, snapshot(Example(text="")))
    steps = [(snapshot(Example(text="")), first_sentence, snapshot(example))]
    low, high = COMPLEX_FOLLOW_UPS if rng.random() < COMPLEX_STORY_RATE else SIMPLE_FOLLOW_UPS
    for _ in range(rng.randint(low, high)):
        before = snapshot(example)
        sentence = rng.choice(FOLLOW_UPS)(rng, context, example)
        if sentence:
            sentence = maybe_inline_front(rng, context, example, sentence, before)
            steps.append((before, sentence, snapshot(example)))
    return steps, story_phrases(domain)


def maybe_inline_front(rng: random.Random, context: StoryContext, example: Example, sentence: str,
                       before: dict) -> str:
    """Sometimes put a component in front of a box inside the sentence that mentions it, editing the diagram too."""
    if rng.random() >= INLINE_FRONT_RATE:
        return sentence
    new_targets = [edge[1] for edge in example.edges if list(edge) not in before["edges"]]
    rewritten = add_inline_front_component(rng, example, sentence, new_targets, context.phrase_for,
                                           context.domain.front_components)
    return rewritten or sentence


def add_story_typos(rng: random.Random, steps: list[tuple[dict, str, dict]], sentences: list[str]):
    return [(before, maybe_typos(rng, sentence), after) for (before, _, after), sentence in zip(steps, sentences)]


def story_phrases(domain: Domain) -> list[str]:
    """Everything a sentence can name, which a rewrite has to keep."""
    return ([phrase for _, phrase in domain.things] + [phrase for _, phrase in domain.front_components]
            + [phrase for _, phrase in domain.steps])


def maybe_typos(rng: random.Random, sentence: str) -> str:
    return add_typos(rng, sentence) if rng.random() < TYPO_SENTENCE_RATE else sentence
