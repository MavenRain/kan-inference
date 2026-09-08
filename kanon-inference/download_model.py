#!/usr/bin/env python3
"""Fetch the pinned public model data, with no repository code or global cache."""

import argparse
import hashlib
import json
from pathlib import Path
import urllib.request


MODEL_ID = "HuggingFaceTB/SmolLM2-135M-Instruct"
REVISION = "12fd25f77366fa6b3b4b768ec3050bf629380bac"
ROOT = Path(__file__).resolve().parent
MODEL_DIR = ROOT / "models" / "SmolLM2-135M-Instruct-int8"
FILES = {
    "onnx/model_int8.onnx": (
        137147867,
        "sha256",
        "a7c33f9ef85d06734cc9d1f943f7e2ba57c77e769df727f4d3e217d9f672b0cc",
    ),
    "tokenizer.json": (2104556, "git-blob-sha1", "f922b1797f0c88e71addc8393787831f2477a4bd"),
    "config.json": (861, "git-blob-sha1", "36293b6099200eb8aeb55ae2c01bca2ba46d80d0"),
    "tokenizer_config.json": (3764, "git-blob-sha1", "8c7b22013909450429303ed10be4398bd63f5457"),
}


def fingerprint(path, algorithm):
    digest = hashlib.sha256() if algorithm == "sha256" else hashlib.sha1()
    if algorithm == "git-blob-sha1":
        digest.update(f"blob {path.stat().st_size}\0".encode())
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=("135m", "360m"), default="135m")
    args = parser.parse_args()
    model_id, revision, model_dir, files = MODEL_ID, REVISION, MODEL_DIR, FILES
    if args.profile == "360m":
        model_id = "HuggingFaceTB/SmolLM2-360M-Instruct"
        revision = "a10cc1512eabd3dde888204e902eca88bddb4951"
        model_dir = ROOT / "models" / "SmolLM2-360M-Instruct-int8"
        files = {
            "onnx/model_int8.onnx": (364564558, "sha256", "cb7375a212a6583cbd96eaa739142f3a1a0d17cbd51043c60f081ea5ce6d21e3"),
            "tokenizer.json": FILES["tokenizer.json"],
            "config.json": (846, "git-blob-sha1", "4f2ae86545bb5c1d4fcc55644deef86be50a7dee"),
        }
    manifest = {"model_id": model_id, "revision": revision, "files": {}}
    for filename, (size, algorithm, expected) in files.items():
        destination = model_dir / filename
        destination.parent.mkdir(parents=True, exist_ok=True)
        valid = (
            destination.is_file()
            and destination.stat().st_size == size
            and fingerprint(destination, algorithm) == expected
        )
        if not valid:
            temporary = destination.with_name(destination.name + ".partial")
            url = f"https://huggingface.co/{model_id}/resolve/{revision}/{filename}"
            written = 0
            try:
                with urllib.request.urlopen(url, timeout=60) as response, temporary.open("wb") as out:
                    while chunk := response.read(1024 * 1024):
                        written += len(chunk)
                        if written > size:
                            raise ValueError(f"size limit exceeded for {filename}")
                        out.write(chunk)
                if written != size or fingerprint(temporary, algorithm) != expected:
                    raise ValueError(f"integrity check failed for {filename}")
                temporary.replace(destination)
            finally:
                temporary.unlink(missing_ok=True)
        manifest["files"][filename] = {
            "size_bytes": size,
            "sha256": fingerprint(destination, "sha256"),
            "source_digest": {"algorithm": algorithm, "value": expected},
        }
        print(json.dumps({"verified": filename, "bytes": size}), flush=True)
    (model_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
