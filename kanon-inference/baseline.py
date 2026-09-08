"""Development baseline for a small, explicit English/Nat expression grammar.

This ranks a supplied pool. It neither reads behavioral oracles nor executes terms.
Unsupported hints or types preserve the supplied order. Supported arithmetic is
compared symbolically, including commutativity, constant folding and identities.
"""

from __future__ import annotations

import re


_IDENTIFIER = r"[A-Za-z_][A-Za-z_0-9']*"
_BINDER = re.compile(r"\(\s*(" + _IDENTIFIER + r")\s*:\s*Nat\s*\)")
_TOKENS = re.compile(r"=>|" + _IDENTIFIER + r"|[0-9]+|[():]")
_WORDS = dict(zip(
    "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty".split(),
    range(21),
))
_ORDINALS = {"first": 0, "earlier": 0, "second": 1, "later": 1, "third": 2}
_OPS = {"natAdd": "add", "natMul": "mul", "natSub": "sub"}


def _number(text: str) -> int | None:
    if text in _WORDS:
        return _WORDS[text]
    if re.fullmatch(r"[0-9]{1,12}", text):
        return int(text)
    return None


def _type_arguments(expected_type: str) -> list[str] | None:
    """Accept exactly named, unrestricted Nat arrows ending in Nat."""
    tail = expected_type.strip()
    names = []
    while (match := _BINDER.match(tail)) is not None:
        names.append(match[1].lower())
        tail = tail[match.end():].lstrip()
        if not tail.startswith("->"):
            return None
        tail = tail[2:].lstrip()
    if tail != "Nat" or len(names) > 8 or len(set(names)) != len(names):
        return None
    return names


def _operand(text: str, names: list[str]):
    text = re.sub(r"^the ", "", text.strip())
    if (number := _number(text)) is not None:
        return ("const", number)
    if text in {"input", "argument"} and len(names) == 1:
        return ("arg", 0)
    if text in names:
        return ("arg", names.index(text))
    if text == "last argument" and names:
        return ("arg", len(names) - 1)
    match = re.fullmatch(r"(first|second|third|earlier|later) argument", text)
    if match and _ORDINALS[match[1]] < len(names):
        return ("arg", _ORDINALS[match[1]])
    return None


def _hint_expression(hint: str, names: list[str]):
    """Recognize complete phrases so unknown or contradictory suffixes fail closed."""
    phrase = " ".join(hint.lower().split()).rstrip(".! ")
    phrase = re.sub(r"^return ", "", phrase)
    if phrase == "the input unchanged" and len(names) == 1:
        return ("arg", 0)
    if (operand := _operand(phrase, names)) is not None:
        return operand
    if len(names) == 1 and phrase in {"double the input", "triple the input", "square the input"}:
        other = ("arg", 0) if phrase.startswith("square") else ("const", 2 if phrase.startswith("double") else 3)
        return ("mul", ("arg", 0), other)
    patterns = (
        (r"add (.+) to (.+)", "add", False),
        (r"increase (.+) by (.+)", "add", False),
        (r"subtract (.+) from (.+)", "sub", True),
        (r"multiply (.+) by (.+)", "mul", False),
        (r"(.+) plus (.+)", "add", False),
        (r"(.+) times (.+)", "mul", False),
    )
    if len(names) == 2:
        pair = (("arg", 0), ("arg", 1))
        aggregates = {
            "the sum of the arguments": ("add", *pair),
            "the product of the arguments": ("mul", *pair),
            "the sum of squares of the arguments": ("add", ("mul", pair[0], pair[0]), ("mul", pair[1], pair[1])),
        }
        if phrase in aggregates:
            return aggregates[phrase]
    else:
        aggregates = {}
    for pattern, operation, reverse in patterns:
        match = re.fullmatch(pattern, phrase)
        if match:
            left_text, right_text = match.groups()
            left = _operand(left_text, names) or aggregates.get(left_text)
            right = _operand(right_text, names) or aggregates.get(right_text)
            # A single nested multiplication permits affine expressions without
            # an unrestricted natural-language parser or arbitrary recursion.
            if right is None and operation == "add":
                scaled = re.fullmatch(r"(.+) times (.+)", right_text)
                if scaled:
                    factor = _operand(scaled[1], names)
                    value = _operand(scaled[2], names)
                    if factor is not None and value is not None:
                        right = ("mul", factor, value)
            if left is not None and right is not None:
                return (operation, right, left) if reverse else (operation, left, right)
    return None


def _parse_candidate(candidate: str, arity: int):
    if len(candidate) > 2048:
        return None
    tokens = []
    end = 0
    for match in _TOKENS.finditer(candidate):
        if candidate[end:match.start()].strip():
            return None
        tokens.append(match[0])
        end = match.end()
    if candidate[end:].strip() or len(tokens) > 256:
        return None
    cursor = 0
    names = []
    if tokens and tokens[0] == "fun":
        cursor = 1
        while cursor < len(tokens) and tokens[cursor] == "(":
            binder = tokens[cursor:cursor + 5]
            if len(binder) != 5 or binder[2:] != [":", "Nat", ")"] or not re.fullmatch(_IDENTIFIER, binder[1]):
                return None
            names.append(binder[1])
            cursor += 5
        if cursor >= len(tokens) or tokens[cursor] != "=>":
            return None
        cursor += 1
    if len(names) != arity or len(set(names)) != len(names):
        return None

    def expression(depth=0):
        nonlocal cursor
        if cursor >= len(tokens) or depth > 32:
            raise ValueError("unsupported expression")
        token = tokens[cursor]
        cursor += 1
        if token == "(":
            value = expression(depth + 1)
            if cursor >= len(tokens) or tokens[cursor] != ")":
                raise ValueError("missing parenthesis")
            cursor += 1
            return value
        if (number := _number(token)) is not None and token.isdigit():
            return ("const", number)
        if token in names:
            return ("arg", names.index(token))
        if token in _OPS:
            return (_OPS[token], expression(depth + 1), expression(depth + 1))
        raise ValueError("unsupported expression")

    try:
        result = expression()
        return result if cursor == len(tokens) else None
    except ValueError:
        return None


def _canonical(expression):
    """A sparse polynomial; truncated subtraction remains an ordered atom."""
    operation = expression[0]
    if operation == "const":
        return (((), expression[1]),) if expression[1] else ()
    if operation == "arg":
        return (((("arg", expression[1]),), 1),)
    left, right = _canonical(expression[1]), _canonical(expression[2])
    if operation == "sub":
        if left == right or not left:
            return ()
        if not right:
            return left
        if len(left) == len(right) == 1 and left[0][0] == right[0][0] == ():
            return _canonical(("const", max(0, left[0][1] - right[0][1])))
        return (((("sub", left, right),), 1),)
    terms = {}
    if operation == "add":
        for monomial, coefficient in (*left, *right):
            terms[monomial] = terms.get(monomial, 0) + coefficient
    else:
        if len(left) * len(right) > 128:
            raise ValueError("symbolic expansion limit")
        for left_monomial, left_coefficient in left:
            for right_monomial, right_coefficient in right:
                monomial = tuple(sorted(left_monomial + right_monomial, key=repr))
                terms[monomial] = terms.get(monomial, 0) + left_coefficient * right_coefficient
    if len(terms) > 128 or any(value.bit_length() > 4096 for value in terms.values()):
        raise ValueError("symbolic size limit")
    return tuple(sorted(terms.items(), key=lambda item: repr(item[0])))


def rank_candidates(request: dict) -> list[str]:
    """Return a stable permutation using only hint, expected type and pool text.

    The compiler remains responsible for scope and type validation. Context is
    deliberately unused: this baseline does not unfold user-defined declarations.
    Even a recognized intent preserves order when no structural match is found.
    """
    candidates = list(request["candidates"])
    names = _type_arguments(request.get("expected_type", ""))
    if names is None or not isinstance(request.get("hint"), str):
        return candidates
    intent = _hint_expression(request["hint"], names)
    if intent is None:
        return candidates
    try:
        expected = _canonical(intent)
    except ValueError:
        return candidates

    def mismatch(candidate):
        parsed = _parse_candidate(candidate, len(names))
        if parsed is None:
            return True
        try:
            return _canonical(parsed) != expected
        except ValueError:
            return True

    return sorted(candidates, key=mismatch)
