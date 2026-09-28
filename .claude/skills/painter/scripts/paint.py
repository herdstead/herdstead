#!/usr/bin/env python3
"""Call OpenAI's GPT Image 2.5 (sunburst by default) and keep a provenance record next to every image.

    paint.py generate --prompt-file P [--out DIR] [--model sunburst|flare] ...
    paint.py edit --image REF [--image REF ...] [--mask M] --prompt-file P ...

`generate` is text -> image. `edit` sends one or more reference images (a screenshot to
redesign, existing sprites for the house style) plus the prompt. Small references are
upscaled with NEAREST first (`--ref-scale`), because a 32 px sprite sent as-is reads as a
blob to the model.

Output goes to a fresh directory (default `build/paint/<time>-<slug>/`, git-ignored). The
script refuses a non-empty `--out` and never writes into `art/` or `assets/`: raw model output
is never an asset. Each run writes `image-<i>.png` and `request.json` (model, parameters,
prompt, references with SHA-256, usage, timing) so every picture that later lands in the
repo can say where it came from.

Needs OPENAI_API_KEY. Standard library only (plus Pillow for reference upscaling).
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

API = "https://api.openai.com/v1/images"
MODELS = {"flare": "gpt-image-2.5-flare", "sunburst": "gpt-image-2.5-sunburst"}
SIZES = ("1024x1024", "1536x1024", "1024x1536", "auto")
QUALITIES = ("low", "medium", "high", "xhigh", "max", "auto")
FORBIDDEN = ("art", "assets")  # repo directories raw output must never land in


def fail(message: str) -> None:
    print(f"paint: {message}", file=sys.stderr)
    raise SystemExit(2)


def repo_root() -> Path:
    here = Path.cwd().resolve()
    for candidate in (here, *here.parents):
        if (candidate / "project.godot").exists():
            return candidate
    return here


def out_dir(requested: str | None, prompt: str) -> Path:
    root = repo_root()
    if requested:
        path = Path(requested).expanduser().resolve()
    else:
        slug = re.sub(r"[^a-z0-9]+", "-", prompt.lower())[:40].strip("-") or "image"
        path = root / "build" / "paint" / f"{time.strftime('%Y%m%d-%H%M%S')}-{slug}"
    for name in FORBIDDEN:
        guarded = (root / name).resolve()
        if path == guarded or guarded in path.parents:
            fail(f"refusing to write raw model output into {guarded}; pixelize it first")
    if path.exists() and any(path.iterdir()):
        fail(f"{path} is not empty; pick a new --out")
    path.mkdir(parents=True, exist_ok=True)
    return path


def reference_bytes(path: Path, scale: str) -> tuple[bytes, dict]:
    from PIL import Image

    data = path.read_bytes()
    info = {"path": str(path), "sha256": hashlib.sha256(data).hexdigest()}
    image = Image.open(io.BytesIO(data))
    factor = 1
    if scale == "auto":
        longest = max(image.size)
        while longest * factor * 2 <= 1024:
            factor *= 2
    else:
        factor = int(scale)
    if factor > 1:
        image = image.resize((image.width * factor, image.height * factor), Image.Resampling.NEAREST)
        buffer = io.BytesIO()
        image.save(buffer, "PNG")
        data = buffer.getvalue()
    info["sent_size"] = list(image.size)
    info["nearest_factor"] = factor
    return data, info


def multipart(fields: dict, files: list[tuple[str, str, bytes]]) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    parts = []
    for key, value in fields.items():
        parts.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode()
        )
    for key, filename, data in files:
        head = (
            f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"; filename="{filename}"\r\n'
            "Content-Type: image/png\r\n\r\n"
        )
        parts.append(head.encode() + data + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def call(endpoint: str, body: bytes, content_type: str, timeout: int) -> dict:
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        fail("OPENAI_API_KEY is not set")
    request = urllib.request.Request(
        f"{API}/{endpoint}",
        data=body,
        headers={"Authorization": f"Bearer {key}", "Content-Type": content_type},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")[:2000]
        fail(f"HTTP {error.code} from images/{endpoint}: {detail}")
    except urllib.error.URLError as error:
        fail(f"network error: {error.reason}")
    raise AssertionError("unreachable")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mode", choices=("generate", "edit"))
    prompt = parser.add_mutually_exclusive_group(required=True)
    prompt.add_argument("--prompt", help="prompt text")
    prompt.add_argument("--prompt-file", help="file holding the prompt (preferred: it is kept verbatim)")
    parser.add_argument("--image", action="append", default=[], help="reference image (edit; repeatable)")
    parser.add_argument("--mask", help="edit mask PNG (transparent = repaint)")
    parser.add_argument("--ref-scale", default="auto", help="NEAREST upscale for references: auto or an integer")
    parser.add_argument("--model", choices=tuple(MODELS), default="sunburst")
    parser.add_argument("--size", choices=SIZES, default="1024x1024")
    parser.add_argument("--quality", choices=QUALITIES, default="medium")
    parser.add_argument("--background", choices=("transparent", "opaque", "auto"), default="auto")
    parser.add_argument("--n", type=int, default=1, help="images per call (1-4)")
    parser.add_argument("--out", help="empty output directory (default build/paint/<time>-<slug>)")
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()

    text = Path(args.prompt_file).read_text() if args.prompt_file else args.prompt
    if not text.strip():
        fail("empty prompt")
    if not 1 <= args.n <= 4:
        fail("--n must be 1-4")
    if args.mode == "generate" and (args.image or args.mask):
        fail("--image / --mask only go with edit")
    if args.mode == "edit" and not args.image:
        fail("edit needs at least one --image")

    target = out_dir(args.out, text)
    params = {
        "model": MODELS[args.model],
        "prompt": text,
        "size": args.size,
        "quality": args.quality,
        "background": args.background,
        "output_format": "png",
        "n": args.n,
    }
    references = []
    started = time.monotonic()
    if args.mode == "generate":
        result = call("generations", json.dumps(params).encode(), "application/json", args.timeout)
    else:
        files = []
        for index, name in enumerate(args.image):
            data, info = reference_bytes(Path(name), args.ref_scale)
            references.append(info)
            files.append(("image[]", f"ref-{index}.png", data))
        if args.mask:
            data, info = reference_bytes(Path(args.mask), "1")
            references.append({**info, "role": "mask"})
            files.append(("mask", "mask.png", data))
        body, content_type = multipart({k: str(v) for k, v in params.items()}, files)
        result = call("edits", body, content_type, args.timeout)
    elapsed = round(time.monotonic() - started, 1)

    written = []
    for index, item in enumerate(result.get("data", [])):
        path = target / f"image-{index}.png"
        path.write_bytes(base64.b64decode(item["b64_json"]))
        written.append(path.name)
        if item.get("revised_prompt"):
            (target / f"image-{index}.revised_prompt.txt").write_text(item["revised_prompt"])
    if not written:
        fail(f"no images in response: {json.dumps(result)[:500]}")

    record = {
        "tool": "painter/paint.py",
        "mode": args.mode,
        "endpoint": f"images/{'generations' if args.mode == 'generate' else 'edits'}",
        "params": params,
        "references": references,
        "seconds": elapsed,
        "usage": result.get("usage"),
        "images": written,
        "created": result.get("created"),
    }
    (target / "request.json").write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"out": str(target), "images": written, "seconds": elapsed, "usage": result.get("usage")}))


if __name__ == "__main__":
    main()
