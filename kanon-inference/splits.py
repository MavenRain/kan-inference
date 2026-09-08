"""Validate frozen module assignments for diagnostic corpus partitioning."""

import hashlib
import json
import re
from typing import Any


SPLITS = ("train", "validation", "test")
SPLIT_UNIT = "independent_module_before_synthetic_augmentation"
MAX_MODULES = 10000
MAX_TASKS = 10000
MAX_PAYLOAD_BYTES = 64 * 1024 * 1024
MANIFEST_KEYS = {"schema_version", "name", "corpus_sha256", "split_unit", "modules"}
MODULE_KEYS = {"module_id", "split", "template_group"}
TASK_KEYS = {"id", "family", "module_id", "source", "candidates", "tests"}


class SplitError(ValueError):
    """A manifest cannot establish the requested diagnostic partition."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise SplitError(message)


def _string(value: Any, label: str) -> None:
    _require(type(value) is str and 0 < len(value) <= 200 and bool(value.strip()),
             f"{label} must be a nonempty string of at most 200 characters")
    _require(not any(ord(character) < 32 or ord(character) == 127 for character in value),
             f"{label} must not contain control characters")
    try:
        value.encode("utf-8")
    except UnicodeError as exc:
        raise SplitError(f"{label} must be valid UTF-8") from exc


def _sha256(value: Any, label: str) -> None:
    _require(type(value) is str and re.fullmatch(r"[0-9a-f]{64}", value) is not None,
             f"{label} must be a lowercase SHA-256 digest")


def _assignments(value: Any, corpus: Any) -> dict[str, str]:
    _require(type(value) is dict and set(value) == MANIFEST_KEYS,
             "Manifest must contain exactly schema_version, name, corpus_sha256, split_unit, modules")
    _require(type(value["schema_version"]) is int and value["schema_version"] == 1,
             "Unsupported split manifest schema version")
    _string(value["name"], "Manifest name")
    _sha256(value["corpus_sha256"], "Manifest corpus_sha256")
    _require(type(value["split_unit"]) is str and value["split_unit"] == SPLIT_UNIT,
             f"Manifest split_unit must be {SPLIT_UNIT}")
    entries = value["modules"]
    _require(type(entries) is list and 1 <= len(entries) <= MAX_MODULES,
             f"Manifest requires between 1 and {MAX_MODULES} module assignments")
    assignments: dict[str, str] = {}
    templates: dict[str, str] = {}
    for entry in entries:
        _require(type(entry) is dict and set(entry) == MODULE_KEYS,
                 "Module assignment must contain exactly module_id, split, template_group")
        _string(entry["module_id"], "Module module_id")
        _string(entry["template_group"], "Module template_group")
        split = entry["split"]
        _require(type(split) is str and split in SPLITS,
                 "Module split must be train, validation, or test")
        module_id = entry["module_id"]
        _require(module_id not in assignments, f"Duplicate module assignment: {module_id}")
        template = entry["template_group"]
        _require(template not in templates or templates[template] == split,
                 f"Template group spans splits: {template}")
        assignments[module_id] = split
        templates[template] = split

    _require(type(corpus) is dict and type(corpus.get("tasks")) is list,
             "Corpus must contain a task list")
    tasks = corpus["tasks"]
    _require(1 <= len(tasks) <= MAX_TASKS,
             f"Corpus requires between 1 and {MAX_TASKS} tasks")
    modules: set[str] = set()
    task_ids: set[str] = set()
    payloads: dict[bytes, str] = {}
    remaining = MAX_PAYLOAD_BYTES
    encoder = json.JSONEncoder(sort_keys=True, separators=(",", ":"),
                               ensure_ascii=False, allow_nan=False)
    for task in tasks:
        _require(type(task) is dict and set(task) == TASK_KEYS,
                 "Corpus tasks must contain exactly id, family, module_id, source, candidates, tests")
        for key in ("id", "family", "module_id"):
            _string(task[key], f"Task {key}")
        _require(task["id"] not in task_ids, f"Duplicate task id: {task['id']}")
        task_ids.add(task["id"])
        module_id = task["module_id"]
        _require(module_id in assignments, f"Missing module assignment: {module_id}")
        modules.add(module_id)
        # Metadata labels cannot disguise an otherwise identical task payload.
        payload = {key: task[key] for key in ("source", "candidates", "tests")}
        digest = hashlib.sha256()
        try:
            for chunk in encoder.iterencode(payload):
                encoded = chunk.encode("utf-8")
                remaining -= len(encoded)
                _require(remaining >= 0, "Corpus task payloads exceed the split validation byte limit")
                digest.update(encoded)
        except (TypeError, ValueError, UnicodeError, RecursionError) as exc:
            if isinstance(exc, SplitError):
                raise
            raise SplitError("Corpus task payload must be finite JSON with valid UTF-8") from exc
        fingerprint = digest.digest()
        previous = payloads.get(fingerprint)
        _require(previous is None or previous == module_id,
                 f"Duplicate task payload across modules: {previous}, {module_id}")
        payloads[fingerprint] = module_id
    unknown = assignments.keys() - modules
    _require(not unknown, "Manifest contains unknown corpus modules: " + ", ".join(sorted(unknown)[:5]))
    return assignments


def validate_manifest(value: Any, corpus: dict[str, Any], corpus_sha256: str) -> dict[str, Any]:
    """Bind assignments to the caller's actual corpus byte hash.

    The caller must validate corpus task semantics before calling this function.
    Assignments and exact-payload checks do not establish independent evaluation.
    """
    _sha256(corpus_sha256, "Actual corpus SHA-256")
    _assignments(value, corpus)
    _require(value["corpus_sha256"] == corpus_sha256,
             "Split manifest corpus_sha256 does not match the actual corpus bytes")
    return value


def select_tasks(corpus: dict[str, Any], manifest: dict[str, Any], split: str) -> list[dict[str, Any]]:
    """Select in corpus order after validate_manifest has bound the corpus bytes."""
    _require(type(split) is str and split in SPLITS,
             "Selected split must be train, validation, or test")
    assignments = _assignments(manifest, corpus)
    tasks = [task for task in corpus["tasks"] if assignments[task["module_id"]] == split]
    _require(bool(tasks), f"Selected split is empty: {split}")
    return tasks
