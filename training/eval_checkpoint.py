"""Run the held-out sentences through the base model plus one LoRA checkpoint.

Usage: eval_checkpoint.py <checkpoint.safetensors> <sentences.txt>
Set TERMAID_REPLY=changes for models trained on change-only replies (see changes.py), or
TERMAID_REPLY=whole for models trained on whole descriptions (see whole_text.py).
"""

import json
import os
import shutil
import sys
import tempfile
import time
from pathlib import Path

from mlx_lm import generate, load
from changes import CHANGES_PROMPT, apply_changes
from generate_data import BASE_MODEL, load_system_prompt
from whole_text import load_whole_text_prompt
from story import format_update_request, split_sentences

MAX_REPLY_TOKENS = 400
MAX_WHOLE_REPLY_TOKENS = 1000
EMPTY_DIAGRAM = {"direction": "LR", "boxes": [], "edges": []}
CHANGE_ONLY = os.environ.get("TERMAID_REPLY") == "changes"
WHOLE_TEXT = os.environ.get("TERMAID_REPLY") == "whole"


def load_with_checkpoint(checkpoint: Path):
    # mlx-lm loads adapters from a directory holding adapters.safetensors and its config.
    with tempfile.TemporaryDirectory() as adapter_dir:
        shutil.copy(checkpoint.parent / "adapter_config.json", adapter_dir)
        shutil.copy(checkpoint, Path(adapter_dir) / "adapters.safetensors")
        return load(BASE_MODEL, adapter_path=adapter_dir)


def format_edges(state: dict) -> str:
    return "\n".join(f"  {source} --{label or ''}--> {target}" for source, target, label in state["edges"])


def run_description(complete, system_prompt: str, description: str) -> dict:
    """Mirrors TextToMermaid.convert: one call per sentence, carrying the diagram forward.

    complete(messages) returns the model's reply, so other models can be tested the same way.
    """
    if WHOLE_TEXT:
        try:
            state = json.loads(complete([{"role": "system", "content": system_prompt},
                                         {"role": "user", "content": description}]))
            if not all(isinstance(edge, list) and len(edge) == 3 for edge in state["edges"]):
                raise ValueError("edge is not [from, to, label]")
            return state
        except (json.JSONDecodeError, KeyError, TypeError, ValueError):
            print("  INVALID JSON")
            return EMPTY_DIAGRAM
    state = EMPTY_DIAGRAM
    for sentence in split_sentences(description):
        messages = [{"role": "system", "content": system_prompt},
                    {"role": "user", "content": format_update_request(state, sentence)}]
        reply = complete(messages)
        try:
            state = apply_changes(state, json.loads(reply)) if CHANGE_ONLY else json.loads(reply)
            if not all(isinstance(edge, list) and len(edge) == 3 for edge in state["edges"]):
                raise ValueError("edge is not [from, to, label]")
        except (json.JSONDecodeError, KeyError, TypeError, ValueError):
            print(f"  INVALID JSON after: {sentence[:60]}")
            state = EMPTY_DIAGRAM
            break
    return state


def print_results(name: str, complete, descriptions_file: Path) -> None:
    system_prompt = CHANGES_PROMPT if CHANGE_ONLY else load_whole_text_prompt() if WHOLE_TEXT else load_system_prompt()
    print(f"######## {name}")
    for description in descriptions_file.read_text().splitlines():
        start = time.perf_counter()
        state = run_description(complete, system_prompt, description)
        print(f"== {description}  ({time.perf_counter() - start:.2f}s)")
        print(format_edges(state))


def main() -> None:
    checkpoint, descriptions_file = Path(sys.argv[1]), Path(sys.argv[2])
    model, tokenizer = load_with_checkpoint(checkpoint)

    def complete(messages):
        prompt = tokenizer.apply_chat_template(messages, add_generation_prompt=True, enable_thinking=False)
        return generate(model, tokenizer, prompt=prompt, max_tokens=MAX_WHOLE_REPLY_TOKENS if WHOLE_TEXT else MAX_REPLY_TOKENS)

    print_results(checkpoint.name, complete, descriptions_file)


if __name__ == "__main__":
    main()
