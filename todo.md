# Todo

- [x] Retrain to fix "nothing leads into X" (v10, 2026-11-03): v9 minus 569 flagged steps plus 298
      connected Sonnet stories. On the 55 holdouts: clean 36 → 42, problems 29 → 16, orphans 22 → 13.
- [ ] Check v10 didn't buy clean diagrams with wrong edges: have Claude (CLI) grade v9 and v10
      holdout diagrams against their descriptions (missing steps, made-up edges, wrong targets)
- [ ] Drop whole v9 stories that contain a flagged step, not just the step (250 finished v9
      diagrams still carry an orphan from an earlier dropped step), and refill with Sonnet stories
- [ ] Target the remaining 13 orphans: stories that bring in a new actor mid-story ("the kitchen",
      "customs") through an existing box, and conditions that only come up late in the story
- [ ] Re-ask the model once when a step adds a findProblems problem (app side; costs one call)
- [ ] Host the model on GitHub Releases / Hugging Face with a download button in setup
