"""Dense stories aimed at the mistakes the grader finds most on the hard descriptions.

The connected stories (connected_stories.py) put one action in each sentence, but people pack two to four
actions and a condition with both of its outcomes into one sentence. On those the model stops the flow
early, drops the "otherwise" path, sends an outcome to the wrong box, or hangs a decision off the wrong
step. Here Claude writes such dense sentences with the full diagram after each one. The topics avoid the
holdout and hard-set topics.

Usage: targeted_stories.py <calls> <stories per call> <model> <output dir> [seed]
Appends the stories that parse to <output dir>/stories.jsonl; build_data.py turns them into steps.
"""

import random
import sys
from pathlib import Path

from connected_stories import build_prompts, collect_stories
from generate_data import load_system_prompt

TOPICS = [
    "hotel housekeeping", "library interlibrary loans", "car rental returns", "warehouse returns", "food truck orders",
    "hospital pharmacy refills", "museum loans of artworks", "wedding venue bookings", "apartment maintenance requests",
    "university course registration", "visa applications", "building permits", "music festival wristbands",
    "airport baggage transfer", "vet clinic appointments", "train ticket refunds", "bank loan approval",
    "credit card disputes", "grocery delivery substitutions", "restaurant reservations", "dry cleaning pickups",
    "bike sharing docks", "parking fines appeals", "electric car charging", "solar panel installation",
    "home inspection before sale", "moving company quotes", "gym membership cancellations", "pharmacy prescription checks",
    "hospital lab samples", "ambulance patient handover", "cargo ship customs clearance", "furniture assembly service",
    "phone repair shop", "software bug triage", "code deployment pipeline", "data center hardware swaps",
    "website domain transfers", "online exam proctoring", "job interview scheduling", "employee onboarding laptops",
    "conference talk submissions", "charity grant payouts", "food bank donations", "community garden plots",
    "city pothole reports", "snow plough dispatch", "water meter readings", "gas leak reports", "fire safety inspections",
    "stair lift installs", "piano tuning visits", "cheese aging cellar", "chocolate tempering line",
    "bakery wholesale orders", "fish market auctions", "dairy farm milk collection", "orchard apple grading",
    "greenhouse watering", "timber mill grading", "textile dye works", "glass bottle recycling deposits",
    "car assembly paint shop", "aircraft cabin cleaning", "cruise ship embarkation", "zoo animal feeding",
    "aquarium water testing", "horse racing entries", "marathon bib collection", "chess tournament pairings",
    "esports ticket resale", "podcast episode publishing", "photo stock submissions", "book printing on demand",
    "comic con badge pickup", "theatre ticket exchanges", "film festival screenings", "art school portfolio reviews",
    "driving test bookings", "passport renewals", "jury of a cooking contest", "tailoring alterations",
    "laundromat machine faults", "hearing aid fittings", "eye exam and glasses orders", "physiotherapy referrals",
    "mortgage document checks", "pension withdrawals", "small claims court filings", "patent applications",
    "election postal votes", "census form follow-up", "lottery prize claims", "casino chip cashout",
    "ski lift maintenance", "harbour berth bookings", "canal lock operation", "toll road billing",
]

INSTRUCTIONS = """Write {count} training stories for a small model that builds a flowchart one sentence at a time.
Topics, one each: {topics}.

The model makes four mistakes on long, dense descriptions. Write stories that force it to get each one right:
1. It stops the flow early. When one sentence chains several actions ("X checks it and passes it to Y,
   which stamps it and files it with Z"), every action becomes an edge, all the way to the last box named.
2. It drops the other outcome. When a sentence says "if ... otherwise ...", "... else ...", "if not ...",
   "the rest go to ...", "anything that fails ...", "those that don't ... get ...", "unless ..., in which
   case ...", the decision gets both a "yes" and a "no" outcome, each going where the text says.
3. It sends an outcome to the wrong box. Each outcome goes to the box the text names for it ("sends it back
   to the clerk" goes to the clerk, not the box that last acted; a new actor named in an outcome gets a new box).
4. It hangs a decision off the wrong step. The decision's one incoming edge comes from the box that makes
   that decision in the text ("if the surgeon accepts" is checked by the surgeon, even if another box sent
   the item to the surgeon); and a decision about something that happens later in the sentence is checked
   by the box that does it.

Each story: 4-6 sentences of natural, varied English, like a person explaining a process to a colleague
(lowercase, run-on sentences and the odd typo are fine). Each sentence carries 2-4 actions, and most
sentences carry a condition with both of its outcomes, sometimes with a further action after an outcome
("otherwise it goes to the supervisor, who phones the customer"). Vary the wording of conditions across
"if", "when", "only if", "unless", "once", "anything that", "those who", "else", "the rest". At least one
outcome loops back to an earlier box ("sends it back to", "tries again"). No sentence may contain ".", "!"
or "?" before its end.
- The first sentence starts the process. Every later sentence continues from a box already in the diagram,
  so the finished flowchart has exactly one starting box that nothing leads into.

After each sentence give the full diagram so far, following the rules a model is given below. On top of
those rules, every diagram must satisfy:
- every box appears in at least one edge, and only the first box has nothing leading into it;
- every decision box has exactly one incoming edge, with an empty label, from the box that checks it;
- a decision's outcomes are at most one "yes" and at most one "no", never both to the same box;
- a different check gets its own decision box, even if the question sounds similar.
Before replying, reread each sentence against its diagram: every action, outcome and named box is drawn.

Rules the model is given:
<rules>
{rules}
</rules>

Answer directly from these instructions; do not use any tools or look at files.
Reply with only JSON: {{"stories": [{{"sentences": ["...", ...], "diagrams": [{{"direction": "LR", "boxes": [...], "edges": [[from, to, label], ...]}}, ...]}}, ...]}}
with exactly one diagram per sentence."""


def main() -> None:
    calls, per_call, model, output = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3], Path(sys.argv[4])
    seed = int(sys.argv[5]) if len(sys.argv) > 5 else 17
    output.mkdir(exist_ok=True)
    prompts = build_prompts(random.Random(seed), calls, per_call, load_system_prompt(), TOPICS, INSTRUCTIONS)
    stories = collect_stories(prompts, model, output / "stories.jsonl")
    print(f"saved {len(stories)} stories to {output / 'stories.jsonl'}")


if __name__ == "__main__":
    main()
