"""Calls Claude through the `claude` CLI in print mode for JSON replies, used to vary the training data."""

import json
import re
import subprocess

SYSTEM_PROMPT = "You write synthetic training data. Reply with only the requested JSON, no prose or code fences."
JSON_OBJECT = re.compile(r"\{.*\}", re.S)


def ask_json(prompt: str, model: str = "haiku") -> object:
    """Returns the parsed JSON reply, or None when the call fails or the reply is not JSON."""
    command = ["claude", "-p", prompt, "--model", model, "--tools", "", "--output-format", "json",
               "--system-prompt", SYSTEM_PROMPT, "--no-session-persistence", "--strict-mcp-config"]
    completed = subprocess.run(command, capture_output=True, text=True, timeout=300, cwd="/tmp")
    try:
        reply = json.loads(completed.stdout)["result"]
        return json.loads(JSON_OBJECT.search(reply).group())
    except (json.JSONDecodeError, KeyError, TypeError, AttributeError):
        return None
