<p align="center"><img src="docs/icon.png" width="128" alt="termaid icon"></p>

# termaid

termaid is a Mac menu-bar app. Describe a process in plain English, typed or spoken, and it draws
a Mermaid flowchart. Speech and diagrams both run on your Mac, so nothing leaves it. Your diagrams
are saved to a Library window, where you can open and export them.

<p align="center">
  <img src="docs/screenshots/termaid-library-grid.png" width="49%" alt="Library grid">
  <img src="docs/screenshots/termaid-library-detail.png" width="49%" alt="Diagram detail">
</p>

## Install

Download `Termaid.zip` from the [latest release](https://github.com/WorldOccupier/termaid/releases/latest),
unzip it and move Termaid to Applications. On first launch the setup screen downloads two models,
about 1.9 GB in total. Hold ⌥ Space to talk, or press ⌥ T to type.

## How it works

termaid sends your description to the model one sentence at a time, along with the diagram so far.
The model replies with JSON, a list of boxes and a list of `[from, to, label]` edges. termaid checks
the JSON and writes the Mermaid itself, so a bad reply can't break the syntax. A condition like "if
the tests fail" becomes a decision box with yes and no branches.

The diagram model is [LiquidAI/LFM3-1.7B](https://huggingface.co/LiquidAI/LFM3-1.7B) with a LoRA
adapter I trained. The weights live on [Hugging Face](https://huggingface.co/VatsaIsHere/termaid),
not in this repo. Speech uses Parakeet.

## Layout

- `src/` is the TypeScript engine. It splits sentences, builds prompts, cleans replies and writes
  Mermaid. It has no Mac code.
- `mac/` is the Swift app. It runs the model with llama.cpp, speech with Parakeet and the engine in
  JavaScriptCore.
- `scripts/` holds development tools.
- `training/` holds data generation, fine-tuning and evaluation.

## Build

You need Node 23.6 or newer and Xcode 26 or newer.

```sh
npm run build:engine     # rerun after changing src/
cd mac && swift build -c release
.build/release/termaid-mac diagram <model.gguf> "build, then test, then deploy"
.build/release/termaid-mac transcribe clip.wav     # 16 kHz mono WAV
```

To run the app with your own model, set `TERMAID_MODEL` to its path.

## Test

```sh
npm test
cd mac && swift test
```

## Training

Training runs on Modal, because Unsloth and MLX don't support LFM3.

```sh
cd training
python connected_stories.py 150 2 sonnet data-sonnet   # about 300 stories, 25 minutes
python build_data.py data-v9 data-v10 data-sonnet/stories.jsonl
TERMAID_DATA=data-v10 uvx modal run --detach modal_train_lfm3.py::main --name lfm3-v10 --steps 520
uvx modal run modal_train_lfm3.py::gguf --name lfm3-v10
mkdir -p gguf && uvx modal volume get termaid-runs lfm3-v10/lfm3-v10-f16.gguf gguf/
llama-quantize gguf/lfm3-v10-f16.gguf gguf/lfm3-v10-q6_k.gguf Q6_K
weight_space/run_eval.sh gguf/lfm3-v10-q6_k.gguf v10-q6k && node weight_space/score.ts v10-q6k base-q6k
```

Check each checkpoint against `holdout.txt`, which never appears in training. Ship Q6_K, not
Q4_K_M. On 55 holdout descriptions, Q6_K matched the unquantized model 27 times and Q4_K_M only 17.

## License

The code is MIT. The model weights fall under the
[LFM Open License v1.0](https://huggingface.co/LiquidAI/LFM3-1.7B/blob/main/LICENSE), which rules
out commercial use by organizations with $10M or more in annual revenue.
