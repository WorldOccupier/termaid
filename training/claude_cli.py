"""Calls Claude through the `claude` CLI in print mode for JSON replies, used to vary the training data.

Every call's cost (as the CLI reports it) is added up, and the total is printed when the script exits.
"""

import atexit
import json
import re
import subprocess
import sys
import threading

SYSTEM_PROMPT = "You write synthetic training data. Reply with only the requested JSON, no prose or code fences."
JSON_OBJECT = re.compile(r"\{.*\}", re.S)


class CostTally:
    """Adds up the CLI's reported cost across threads."""

    def __init__(self) -> None:
        self.calls = 0
        self.usd = 0.0
        self._lock = threading.Lock()

    def add(self, usd: float) -> None:
        with self._lock:
            self.calls += 1
            self.usd += usd

    def report(self) -> None:
        if self.calls:
            print(f"Claude CLI: {self.calls} calls, ${self.usd:.4f} at API rates", file=sys.stderr)


spent = CostTally()
atexit.register(spent.report)


def ask_json(prompt: str, model: str = "haiku", system_prompt: str = SYSTEM_PROMPT) -> object:
    """Returns the parsed JSON reply, or None when the call fails or the reply is not JSON."""
    command = ["claude", "-p", prompt, "--model", model, "--tools", "", "--output-format", "json",
               "--system-prompt", system_prompt, "--no-session-persistence", "--strict-mcp-config"]
    completed = subprocess.run(command, capture_output=True, text=True, timeout=300, cwd="/tmp")
    try:
        envelope = json.loads(completed.stdout)
    except json.JSONDecodeError:
        return None
    spent.add(float(envelope.get("total_cost_usd") or 0))
    try:
        return json.loads(JSON_OBJECT.search(envelope["result"]).group())
    except (json.JSONDecodeError, KeyError, TypeError, AttributeError):
        return None
