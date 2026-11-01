"""Ask Claude for many extra vocabulary packs, saved to generated_domains.json.

The hand-written packs in domains.py cover six fields, so the model learned their words. These add
dozens more. Legal, manufacturing and education stay out on purpose: the held-out descriptions use
them to check the model handles fields it never saw.

Usage: generate_domains.py   (needs the `claude` CLI, logged in)
"""

import json
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from domains import Domain
from claude_cli import ask_json

OUTPUT = Path(__file__).parent / "generated_domains.json"
ATTEMPTS_PER_TOPIC = 3
WORKERS = 8

TOPICS = [
    "airline check-in and boarding", "hotel reservations and housekeeping", "insurance claims",
    "real estate sales", "construction site management", "farming and harvest", "bank loan approval",
    "customer support tickets", "book publishing", "film production", "professional sports team operations",
    "event and concert planning", "public library", "emergency police dispatch", "fire department response",
    "pharmaceutical drug trials", "research laboratory", "mobile phone carrier", "electric power grid",
    "water treatment plant", "warehouse robots", "ride-sharing app", "food delivery app", "online store returns",
    "employee onboarding", "procurement and purchasing", "IT helpdesk", "multiplayer game servers",
    "smart home devices", "machine learning training pipeline", "data warehouse ETL pipeline", "payment processing",
    "social media content moderation", "email marketing campaigns", "veterinary clinic", "dental office",
    "car repair shop", "airport baggage handling", "city permit office", "nonprofit donations",
    "streaming video platform", "cybersecurity incident response", "cloud infrastructure deployment",
    "mobile app release", "newsroom publishing", "museum exhibitions", "gym membership", "wedding planning",
    "space mission control", "train operations", "shipping port containers", "blood bank", "elections and vote counting",
    "tax filing", "travel booking site", "subscription billing", "chat app messaging backend", "search engine indexing",
]

PROMPT = """Write a vocabulary pack for describing workflows and systems in this field: {topic}.
Reply with JSON exactly in this shape, all strings in plain lowercase English except box names:
{{
  "things": [["<Box Name, 1-3 words, Title Case>", "<how a person refers to it in a sentence, e.g. 'the front desk'>"], ...],
  "verbs": [["<edge label, 1-3 words, e.g. 'sends to'>", "<verb phrase that goes right before the target, e.g. 'sends the form to'>"], ...],
  "conditions": [["<yes/no decision box, short question ending in '?', e.g. 'Room ready?'>", ["<clause saying it is true, e.g. 'the room is ready'>", "<another wording>", ...]], ...],
  "thing_conditions": [["{{}} <state>?", "{{}} is <state>"], ...],
  "steps": [["<Step Box, 1-3 words>", "<imperative phrase, e.g. 'check the passport'>"], ...],
  "step_outcomes": [["<question ending in '?' about the last step, e.g. 'Passed?'>", ["<clause saying it went well, e.g. 'it passes'>", ...]], ...],
  "front_components": [["<Box Name>", "<noun phrase without 'the', for 'there is a ___ in front of ...'>"], ...],
  "replicable": <true if things in this field can be multiple interchangeable instances, like servers or counters>
}}
Give 14 things, 12 verbs, 7 conditions with 2-3 wordings each, 3 thing_conditions (they must contain
"{{}}" where the thing goes), 12 steps, 3 step_outcomes and 3 front_components. Use realistic names
from this field, all different from each other. Front components must be new boxes, not any of the
things, and every box name must share a word with how sentences refer to it."""


def valid_pairs(pairs, minimum: int) -> bool:
    return (isinstance(pairs, list) and len(pairs) >= minimum
            and all(isinstance(p, list) and len(p) == 2 and all(isinstance(s, str) and s.strip() for s in p) for p in pairs))


def valid_question_pairs(pairs, minimum: int) -> bool:
    return (isinstance(pairs, list) and len(pairs) >= minimum
            and all(isinstance(p, list) and len(p) == 2 and isinstance(p[0], str) and p[0].endswith("?")
                    and isinstance(p[1], list) and p[1] and all(isinstance(s, str) and s.strip() for s in p[1]) for p in pairs))


NAME_FILLER = {"the", "a", "an", "of", "to", "for", "and"}


def names_match(box: str, phrase: str) -> bool:
    """A box must share a word with how sentences name it, or the model learns to invent box names."""
    def words(text):
        return {w for w in re.findall(r"[a-z0-9]+", text.lower()) if w not in NAME_FILLER}
    return bool(words(box) & words(phrase))


def to_domain(topic: str, reply) -> Domain:
    """Raises ValueError for packs that would make broken examples: missing parts, duplicates, bad placeholders."""
    if not isinstance(reply, dict):
        raise ValueError("reply is not a JSON object")
    parts_ok = (valid_pairs(reply.get("things"), 10) and valid_pairs(reply.get("verbs"), 8)
                and valid_question_pairs(reply.get("conditions"), 5) and valid_pairs(reply.get("thing_conditions"), 1)
                and valid_pairs(reply.get("steps"), 8) and valid_question_pairs(reply.get("step_outcomes"), 2)
                and valid_pairs(reply.get("front_components"), 0) and isinstance(reply.get("replicable"), bool))
    if not parts_ok:
        raise ValueError("a part is missing, too short or malformed")
    things = [tuple(t) for t in reply["things"] if names_match(*t)]
    if len(things) < 10:
        raise ValueError("too few things whose box name matches how sentences refer to them")
    if len({b.lower() for b, _ in things}) < len(things) or len({p.lower() for _, p in things}) < len(things):
        raise ValueError("duplicate things")
    if not all(q.count("{}") == 1 and t.count("{}") == 1 for q, t in reply["thing_conditions"]):
        raise ValueError("thing_conditions without one {} placeholder")
    # A front component reusing a thing's box name would draw that box for a different phrase.
    box_names = {b.lower() for b, _ in things}
    front = [tuple(f) for f in reply["front_components"] if names_match(*f) and f[0].lower() not in box_names]
    # No front components is fine: front_component() then never picks this domain's boxes.
    return Domain(name=topic, things=things, verbs=[tuple(v) for v in reply["verbs"]],
                  conditions=[(q, w) for q, w in reply["conditions"]],
                  thing_conditions=[tuple(t) for t in reply["thing_conditions"]],
                  steps=[tuple(s) for s in reply["steps"]],
                  step_outcomes=[(q, w) for q, w in reply["step_outcomes"]],
                  front_components=front, replicable=reply["replicable"])


def make_domain(topic: str) -> Domain | None:
    for _ in range(ATTEMPTS_PER_TOPIC):
        try:
            domain = to_domain(topic, ask_json(PROMPT.format(topic=topic), model="sonnet"))
            print(f"ok   {topic}", file=sys.stderr)
            return domain
        except ValueError as error:
            print(f"retry {topic}: {error}", file=sys.stderr)
    print(f"FAIL {topic}", file=sys.stderr)
    return None


def main() -> None:
    # Keep packs from an earlier run, so a rerun only retries the topics that failed.
    domains = json.loads(OUTPUT.read_text()) if OUTPUT.exists() else []
    done = {domain["name"] for domain in domains}
    with ThreadPoolExecutor(WORKERS) as pool:
        domains += [d.__dict__ for d in pool.map(make_domain, [t for t in TOPICS if t not in done]) if d]
    OUTPUT.write_text(json.dumps(domains, indent=1))
    print(f"wrote {len(domains)}/{len(TOPICS)} domains to {OUTPUT}")


if __name__ == "__main__":
    main()
