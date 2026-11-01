"""Run the held-out sentences through a stock Ollama model, the same way eval_checkpoint.py does.

Usage: eval_ollama.py <ollama model> <sentences.txt>   (needs `ollama serve`)
"""

import json
import os
import sys
import urllib.request
from pathlib import Path

from eval_checkpoint import MAX_REPLY_TOKENS, MAX_WHOLE_REPLY_TOKENS, WHOLE_TEXT, print_results

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")


def main() -> None:
    model, descriptions_file = sys.argv[1], Path(sys.argv[2])

    def complete(messages):
        body = json.dumps({"model": model, "messages": messages, "stream": False, "format": "json", "think": False,
                           "options": {"temperature": 0, "num_predict": MAX_WHOLE_REPLY_TOKENS if WHOLE_TEXT else MAX_REPLY_TOKENS}}).encode()
        request = urllib.request.Request(f"{OLLAMA_URL}/api/chat", body, {"Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=300) as response:
            return json.load(response)["message"]["content"]

    print_results(model, complete, descriptions_file)


if __name__ == "__main__":
    main()
