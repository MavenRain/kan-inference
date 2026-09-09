"""Frozen candidate ranking rules, independent of models and benchmark data."""

import hashlib
import math
from pathlib import Path


DEFAULT_PROFILE = "conditional-v1"
PROFILES = {
    "conditional-v1": {"version": "mean-token-logprob-v1"},
    "hint-calibrated-v1": {"version": "hint-free-mean-logprob-difference-v1"},
}
SCORING_CODE_SHA256 = hashlib.sha256(Path(__file__).resolve().read_bytes()).hexdigest()


def scoring_code_hash():
    return SCORING_CODE_SHA256


def provenance(profile=DEFAULT_PROFILE):
    return {
        "scoring_profile": profile,
        "scoring_version": PROFILES[profile]["version"],
        "scoring_code_sha256": scoring_code_hash(),
    }


def reference_request(request):
    """Remove only the current hint, preserving the goal and source context."""
    return {**request, "hint": ""}


def rank_scores(conditional_scores, reference_scores=None, profile=DEFAULT_PROFILE):
    """Return scores in pool order, rejecting nonfinite inputs and differences."""
    if profile not in PROFILES:
        raise ValueError("unknown scoring profile")
    if not conditional_scores or not all(math.isfinite(value) for value in conditional_scores):
        raise ValueError("model produced nonfinite or empty conditional scores")
    if profile == DEFAULT_PROFILE:
        if reference_scores is not None:
            raise ValueError("conditional scoring does not accept reference scores")
        return list(conditional_scores)
    if reference_scores is None or len(reference_scores) != len(conditional_scores):
        raise ValueError("reference scores must match the candidate pool")
    if not all(math.isfinite(value) for value in reference_scores):
        raise ValueError("model produced nonfinite reference scores")
    scores = [conditional - reference
              for conditional, reference in zip(conditional_scores, reference_scores)]
    if not all(math.isfinite(value) for value in scores):
        raise ValueError("model produced nonfinite ranking scores")
    return scores


def ranked_indices(scores):
    """Break equal scores by their original candidate index."""
    if not scores or not all(math.isfinite(value) for value in scores):
        raise ValueError("ranking requires finite nonempty scores")
    return sorted(range(len(scores)), key=lambda index: (-scores[index], index))
