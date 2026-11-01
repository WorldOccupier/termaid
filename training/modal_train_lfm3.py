"""Fine-tune LFM3-1.7B on termaid's per-sentence JSON diagram steps with LoRA on Modal.

The existing modal_train.py uses Unsloth, which does not know LFM3's custom architecture. This
script uses plain Transformers plus PEFT and the same prompt/completion masking as the MLX runs.

Usage:
  uvx modal run --detach modal_train_lfm3.py::main --name lfm3-json-v1 --steps 300
  uvx modal run modal_train_lfm3.py::main --name lfm3-smoke --steps 2

Evaluate on held-out descriptions (same output format as eval_checkpoint.py):
  uvx modal run modal_train_lfm3.py::evaluate_holdout --name lfm3-json-v1 --descriptions holdout.txt
  uvx modal run modal_train_lfm3.py::evaluate_holdout --name lfm3-whole-g1 --descriptions holdout.txt --whole-text

Export a merged f16 GGUF (then quantize locally with llama-quantize):
  uvx modal run modal_train_lfm3.py::gguf --name lfm3-json-v1

Fetch the adapter afterwards:
  uvx modal volume get termaid-runs lfm3-json-v1/lora ./lfm3-json-v1-lora
"""

import json
import os
from dataclasses import dataclass
from pathlib import Path

import modal

TRAINING_DIR = Path(__file__).parent
DATA_DIR = TRAINING_DIR / os.environ.get("TERMAID_DATA", "data-v6")
MODEL_ID = "LiquidAI/LFM3-1.7B"
MAX_LENGTH = 2048
# Attention, the gated MLP, and the short-convolution blocks. LFM3 has no separate up/down
# projections; w1/w2/w3 and in_proj/out_proj are its names.
TARGET_MODULES = [
    "q_proj", "k_proj", "v_proj", "o_proj", "gate_proj",
    "w1", "w2", "w3", "in_proj", "out_proj",
]

app = modal.App("termaid-lfm3")
volume = modal.Volume.from_name("termaid-runs", create_if_missing=True)

base_image = (
    modal.Image.debian_slim(python_version="3.12")
    .pip_install(
        "torch==2.15.0",
        "transformers==5.22.1",
        "peft==0.21.2",
        "accelerate==1.15.0",
        "datasets==5.1.0",
        "sentencepiece",
        "protobuf",
    )
    .env({"HF_HOME": "/runs/hf", "TOKENIZERS_PARALLELISM": "false"})
)
image = base_image.add_local_dir(DATA_DIR, "/data")


def read_jsonl(path: Path) -> list[dict]:
    with path.open() as handle:
        return [json.loads(line) for line in handle if line.strip()]


def encode_record(record: dict, tokenizer, max_length: int) -> dict | None:
    """Tokenize one chat record and mask the prompt so loss is only on the JSON reply."""
    messages = record["messages"]
    prompt = tokenizer.apply_chat_template(
        messages[:-1], tokenize=False, add_generation_prompt=True, enable_thinking=False
    )
    full = tokenizer.apply_chat_template(
        messages, tokenize=False, add_generation_prompt=False, enable_thinking=False
    )
    prompt_ids = tokenizer(prompt, add_special_tokens=False)["input_ids"]
    full_ids = tokenizer(full, add_special_tokens=False)["input_ids"]
    if full_ids[: len(prompt_ids)] != prompt_ids:
        raise ValueError("prompt is not a prefix of the full conversation")
    if len(prompt_ids) >= max_length:
        return None
    labels = [-100] * len(prompt_ids) + full_ids[len(prompt_ids) :]
    input_ids = full_ids[:max_length]
    return {
        "input_ids": input_ids,
        "labels": labels[:max_length],
        "attention_mask": [1] * len(input_ids),
    }


@dataclass
class PadBatch:
    pad_token_id: int

    def __call__(self, features: list[dict]) -> dict:
        import torch

        width = max(len(feature["input_ids"]) for feature in features)
        input_ids, labels, attention_mask = [], [], []
        for feature in features:
            padding = width - len(feature["input_ids"])
            input_ids.append(feature["input_ids"] + [self.pad_token_id] * padding)
            labels.append(feature["labels"] + [-100] * padding)
            attention_mask.append(feature["attention_mask"] + [0] * padding)
        return {
            "input_ids": torch.tensor(input_ids, dtype=torch.long),
            "labels": torch.tensor(labels, dtype=torch.long),
            "attention_mask": torch.tensor(attention_mask, dtype=torch.long),
        }


@app.function(image=image, gpu="H100", volumes={"/runs": volume}, timeout=2 * 60 * 60)
def train(
    name: str,
    steps: int,
    learning_rate: float,
    batch_size: int,
    grad_accum: int,
    lora_rank: int,
) -> None:
    import torch
    from datasets import Dataset
    from peft import LoraConfig, get_peft_model
    from transformers import AutoModelForCausalLM, AutoTokenizer, Trainer, TrainingArguments

    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, trust_remote_code=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
    tokenizer.padding_side = "right"

    records = read_jsonl(Path("/data/train.jsonl"))
    encoded = [encode_record(record, tokenizer, MAX_LENGTH) for record in records]
    encoded = [example for example in encoded if example is not None]
    lengths = sorted(len(example["input_ids"]) for example in encoded)
    print(f"{len(encoded)} training examples, tokens median={lengths[len(lengths) // 2]} max={lengths[-1]}")

    dataset = Dataset.from_list(encoded)
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_ID,
        trust_remote_code=True,
        dtype=torch.bfloat16,
        attn_implementation="eager",
    )
    model.config.use_cache = False
    model.gradient_checkpointing_enable(gradient_checkpointing_kwargs={"use_reentrant": False})
    if hasattr(model, "enable_input_require_grads"):
        model.enable_input_require_grads()

    lora = LoraConfig(
        r=lora_rank,
        lora_alpha=lora_rank,
        lora_dropout=0.05,
        bias="none",
        task_type="CAUSAL_LM",
        target_modules=TARGET_MODULES,
    )
    model = get_peft_model(model, lora)
    model.print_trainable_parameters()

    arguments = TrainingArguments(
        output_dir="/tmp/lfm3-out",
        per_device_train_batch_size=batch_size,
        gradient_accumulation_steps=grad_accum,
        max_steps=steps,
        learning_rate=learning_rate,
        warmup_steps=max(1, min(10, steps // 10)),
        lr_scheduler_type="linear",
        optim="adamw_torch",
        bf16=True,
        logging_steps=1 if steps <= 20 else 10,
        save_strategy="no",
        report_to="none",
        seed=3407,
        gradient_checkpointing=True,
        remove_unused_columns=False,
        dataloader_num_workers=2,
    )
    trainer = Trainer(
        model=model,
        args=arguments,
        train_dataset=dataset,
        data_collator=PadBatch(tokenizer.pad_token_id),
        processing_class=tokenizer,
    )
    trainer.train()

    run_dir = Path("/runs") / name
    run_dir.mkdir(parents=True, exist_ok=True)
    model.save_pretrained(run_dir / "lora")
    tokenizer.save_pretrained(run_dir / "lora")
    volume.commit()

    sample = read_jsonl(Path("/data/valid.jsonl"))[0]["messages"]
    prompt = tokenizer.apply_chat_template(
        sample[:-1], tokenize=False, add_generation_prompt=True, enable_thinking=False
    )
    inputs = tokenizer(prompt, return_tensors="pt").to(model.device)
    model.config.use_cache = True
    model.eval()
    with torch.no_grad():
        output = model.generate(**inputs, max_new_tokens=256, do_sample=False)
    reply = tokenizer.decode(output[0][inputs["input_ids"].shape[1] :], skip_special_tokens=True)
    print("SAMPLE REPLY")
    print(reply)
    print(f"saved adapter to /runs/{name}/lora")


@app.local_entrypoint()
def main(
    name: str = "lfm3-json-v1",
    steps: int = 300,
    learning_rate: float = 1e-4,
    batch_size: int = 4,
    grad_accum: int = 4,
    lora_rank: int = 16,
) -> None:
    train.remote(name, steps, learning_rate, batch_size, grad_accum, lora_rank)


eval_image = image.add_local_python_source("story", "domains", "follow_ups", "generate_data")
EMPTY_DIAGRAM = {"direction": "LR", "boxes": [], "edges": []}
MAX_PER_SENTENCE_REPLY_TOKENS = 400
MAX_WHOLE_TEXT_REPLY_TOKENS = 1000


def parse_diagram(reply: str) -> dict:
    diagram = json.loads(reply)
    if not all(isinstance(edge, list) and len(edge) == 3 for edge in diagram["edges"]):
        raise ValueError("edge is not [from, to, label]")
    return diagram


def run_whole_text(complete, system_prompt: str, description: str) -> tuple[dict, str | None]:
    reply = complete(system_prompt, description, MAX_WHOLE_TEXT_REPLY_TOKENS)
    try:
        return parse_diagram(reply), None
    except (json.JSONDecodeError, KeyError, TypeError, ValueError):
        return EMPTY_DIAGRAM, "  INVALID JSON"


def run_per_sentence(complete, system_prompt: str, description: str) -> tuple[dict, str | None]:
    """Mirror eval_checkpoint.run_description: one call per sentence, carrying the diagram forward."""
    from story import format_update_request, split_sentences

    diagram = EMPTY_DIAGRAM
    for sentence in split_sentences(description):
        reply = complete(system_prompt, format_update_request(diagram, sentence), MAX_PER_SENTENCE_REPLY_TOKENS)
        try:
            diagram = parse_diagram(reply)
        except (json.JSONDecodeError, KeyError, TypeError, ValueError):
            return EMPTY_DIAGRAM, f"  INVALID JSON after: {sentence[:60]}"
    return diagram, None


@app.function(image=eval_image, gpu="H100", volumes={"/runs": volume}, timeout=60 * 60)
def evaluate(name: str, system_prompt: str, descriptions: list[str], whole_text: bool) -> str:
    import time

    import torch
    from peft import PeftModel
    from transformers import AutoModelForCausalLM, AutoTokenizer

    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, trust_remote_code=True)
    base = AutoModelForCausalLM.from_pretrained(MODEL_ID, trust_remote_code=True, dtype=torch.bfloat16).to("cuda")
    model = PeftModel.from_pretrained(base, f"/runs/{name}/lora").merge_and_unload().eval()

    def complete(system: str, user: str, max_tokens: int) -> str:
        messages = [{"role": "system", "content": system}, {"role": "user", "content": user}]
        prompt = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True, enable_thinking=False
        )
        inputs = tokenizer(prompt, return_tensors="pt", add_special_tokens=False).to("cuda")
        with torch.no_grad():
            output = model.generate(**inputs, max_new_tokens=max_tokens, do_sample=False)
        return tokenizer.decode(output[0][inputs["input_ids"].shape[1] :], skip_special_tokens=True)

    run_description = run_whole_text if whole_text else run_per_sentence
    lines = [f"######## {name} ({'whole-text' if whole_text else 'per-sentence'})"]
    for description in descriptions:
        start = time.perf_counter()
        diagram, problem = run_description(complete, system_prompt, description)
        lines.extend([problem] if problem else [])
        lines.append(f"== {description}  ({time.perf_counter() - start:.2f}s)")
        lines.extend(f"  {source} --{label or ''}--> {target}" for source, target, label in diagram["edges"])
    return "\n".join(lines) + "\n"


@app.local_entrypoint()
def evaluate_holdout(name: str = "lfm3-json-v1", descriptions: str = "holdout.txt", whole_text: bool = False) -> None:
    from generate_data import load_system_prompt
    from whole_text import load_whole_text_prompt

    path = TRAINING_DIR / descriptions
    system_prompt = load_whole_text_prompt() if whole_text else load_system_prompt()
    result = evaluate.remote(name, system_prompt, path.read_text().splitlines(), whole_text)
    out = TRAINING_DIR / f"eval-{name}-{path.stem}.log"
    out.write_text(result)
    print(result)
    print(f"wrote {out.name}")


gguf_image = base_image.apt_install("git").run_commands(
    "git clone --depth 1 https://github.com/ggml-org/llama.cpp /llama.cpp",
    "pip install /llama.cpp/gguf-py numpy",
)


@app.function(image=gguf_image, gpu="H100", volumes={"/runs": volume}, timeout=60 * 60)
def export_gguf(name: str) -> str:
    """Merge the LoRA into LFM3 and convert the fused model to an f16 GGUF on the volume."""
    import subprocess

    import torch
    from peft import PeftModel
    from transformers import AutoModelForCausalLM, AutoTokenizer

    fused = Path(f"/runs/{name}/fused")
    base = AutoModelForCausalLM.from_pretrained(MODEL_ID, trust_remote_code=True, dtype=torch.bfloat16)
    PeftModel.from_pretrained(base, f"/runs/{name}/lora").merge_and_unload().save_pretrained(fused)
    AutoTokenizer.from_pretrained(MODEL_ID, trust_remote_code=True).save_pretrained(fused)
    out = f"/runs/{name}/{name}-f16.gguf"
    subprocess.run(["python", "/llama.cpp/convert_hf_to_gguf.py", str(fused), "--outfile", out,
                    "--outtype", "f16"], check=True)
    volume.commit()
    return out


@app.local_entrypoint()
def gguf(name: str = "lfm3-json-v1") -> None:
    print(f"wrote {export_gguf.remote(name)}")
    print(f"fetch: uvx modal volume get termaid-runs {name}/{name}-f16.gguf gguf/")
