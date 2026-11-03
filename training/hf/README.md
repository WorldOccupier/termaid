---
base_model: LiquidAI/LFM3-1.7B
license: other
license_name: lfm1.0
license_link: https://huggingface.co/LiquidAI/LFM3-1.7B/blob/main/LICENSE
library_name: gguf
pipeline_tag: text-generation
tags: [gguf, lora, flowchart, mermaid, diagram]
---

# termaid

This is the diagram model behind [termaid](https://github.com/WorldOccupier/termaid), a Mac
menu-bar app. You type or say what a process does in plain English, and termaid draws it as a
Mermaid flowchart. The model runs entirely on your Mac.

It's [LiquidAI/LFM3-1.7B](https://huggingface.co/LiquidAI/LFM3-1.7B) with a LoRA adapter merged
in, quantized to Q6_K. The file is 1.43 GB.

## What it does

termaid feeds the model one sentence at a time, along with the diagram so far. The model sends back
the updated diagram as compact JSON, a list of `boxes` and a list of edges written as
`[from, to, label]`. It never writes Mermaid. termaid checks the JSON and builds the Mermaid itself,
so a bad reply can't produce broken syntax. A condition like "if the tests fail" becomes a decision
box with yes and no branches.

Don't expect it to chat. I trained it only on this per-sentence JSON format, and it won't write
Mermaid if you ask it to.

## Files

| File | Quant | Size |
|---|---|---|
| `termaid.gguf` | Q6_K | 1.43 GB |

I ship Q6_K because Q4_K_M lost too much. On 55 holdout descriptions with v10, Q6_K matched the
unquantized model's diagram 27 times and Q4_K_M only 17 times. Q4_K_M was about 15% faster, which
isn't worth it.

## Usage

The simplest route is the termaid app. Pick this file on the setup screen and the app runs it with
llama.cpp.

To run it yourself, use LFM3's chat template with an empty `<think></think>` block and temperature
0. That matches how I trained it, with thinking turned off. Here's an Ollama Modelfile.

```
FROM ./termaid.gguf
TEMPLATE """{{- if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{ end }}
{{- range .Messages }}
{{- if eq .Role "user" }}<|im_start|>user
{{ .Content }}<|im_end|>
{{ else if eq .Role "assistant" }}<|im_start|>assistant
<think></think>{{ .Content }}<|im_end|>
{{ end }}
{{- end }}<|im_start|>assistant
<think></think>"""
PARAMETER stop "<|im_end|>"
PARAMETER temperature 0
```

You'll also need the system prompt and the per-sentence message format. Both live in the termaid
repo under `src/`.

## Training

I trained a rank-16 LoRA on LFM3-1.7B on Modal, merged it into the base model, and converted the
result to GGUF. The run took 628 steps at an effective batch size of 16, about 1.33 epochs. A
learning rate of 1e-4 diverged.

The data has 7,550 training steps and 565 validation steps. Each step is one sentence, the
diagram before it, and the diagram after it. They come from three places.

- Template stories using vocabulary from software, hiring, healthcare, logistics, finance and
  kitchens.
- About 300 long stories that Claude Sonnet wrote so that every sentence continues the flow.
- About 300 stories aimed at two mistakes v10 kept making. It sent outcomes to the wrong box, and
  it hung decisions off the wrong step.

Any step whose target diagram failed termaid's own structure checks got dropped.

## Evaluation

None of these descriptions appear in the training data.

The 55 regular holdouts include domains the model never saw, such as education, legal and
manufacturing.

| | v10 | v11 |
|---|---|---|
| Valid diagrams | 55 | 55 |
| Clean, no structure problems | 42 | 41 |
| Decisions with both outcomes | 45/59 | 46/61 |

The 40 hard descriptions are long and dense. Claude Sonnet graded each diagram against its
description.

| | v10 | v11 |
|---|---|---|
| Correct, 0 major errors | 1 | 2 |
| At most 2 major errors | 7 | 15 |
| Total major errors | 152 | 137 |
| Wrong target | 43 | 35 |

Sonnet graded each diagram once, so treat a difference of 5 errors or so as noise. The drop in
wrong targets is bigger than that, and so is the jump from 7 to 15 nearly-right diagrams.

## Limitations

The model still struggles with long sentences that pack in several steps. It often handles the
first half and drops the rest, so you lose an "otherwise" branch or the flow stops early. More
training data barely moved this between v10 and v11. Now and then it adds an edge or box the text
never mentioned. I've only trained and tested it on English.

## License

The weights derive from LFM3-1.7B, so the
[LFM Open License v1.0](https://huggingface.co/LiquidAI/LFM3-1.7B/blob/main/LICENSE) covers them.
That license excludes commercial use by organizations with $10M or more in annual revenue. The
termaid app code is MIT.
