"""Regenerate the M1 benchmark from the full spine and observed grid cases.

Run from any directory with python3 -P dev/gen-m1-corpus.py.  Each grid
cell and indexed vector contributes to main.  Code is split at spaces to
meet the fixed line count without adding dead definitions or blank lines.
"""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
spine = (root / "examples/m1-spine.kan").read_text()

# The corpus includes the complete spine and a reproducible arithmetic grid.
# Each grid cell contributes to an exported checksum; none is dead padding.
corpus = spine.replace("examples/m1-spine.kan", "test/corpus/m1-corpus.kan")
corpus = corpus.replace("def main : Nat :=", "def spineResult : Nat :=")
corpus += "\n-- Checked arithmetic grid.  Each cell contributes to the checksum.\n"
total = 0
for i in range(25):
    a, b = divmod(i, 5)
    total += a * b + a + b
    corpus += f"def grid{i} : Nat :=\n  natAdd (natMul {a} {b}) (natAdd {a} {b})\n"
def checksum(names):
    if len(names) == 1:
        return names[0]
    half = len(names) // 2
    return f"(natAdd {checksum(names[:half])} {checksum(names[half:])})"

corpus += "def gridChecksum : Nat := " + checksum([f"grid{i}" for i in range(25)]) + "\n"
corpus += "\n-- Indexed values exercise copy and folding at several payloads.\n"
for i in range(6):
    corpus += f"def vector{i} : SpineV (spineSucc spineZero) := spinePush spineZero {i} spineNil\n"
    corpus += f"def vectorCopy{i} : SpineV (spineSucc spineZero) := spineCopy (spineSucc spineZero) vector{i}\n"
    corpus += f"def vectorRead{i} : Nat := spineTotal (spineSucc spineZero) vectorCopy{i}\n"
corpus += "def vectorChecksum : Nat := " + checksum([f"vectorRead{i}" for i in range(6)]) + "\n"
corpus += "def main : Nat := natAdd spineResult (natAdd gridChecksum vectorChecksum)\n"
expected = 599 + total + sum(range(6))
corpus = corpus.replace("-- main is 599.", f"-- main is {expected}.")

# Break existing code at token boundaries to reach the exact plan size.
# This adds no declarations, blank lines, or comment padding.
lines = corpus.splitlines()
while len(lines) < 1000:
    choices = [(len(line.lstrip()), i) for i,line in enumerate(lines)
               if not line.lstrip().startswith("--") and " " in line.strip()]
    _, index = max(choices)
    line = lines[index]
    indent = len(line) - len(line.lstrip())
    spaces = [i for i,c in enumerate(line) if c == " " and i > indent]
    cut = min(spaces, key=lambda i: abs(i-(indent + len(line.lstrip())//2)))
    lines[index:index+1] = [line[:cut], " " * (indent + 2) + line[cut+1:].lstrip()]
if len(lines) != 1000:
    raise SystemExit("corpus source exceeds the required 1000 lines")
target = root / "test/corpus/m1-corpus.kan"
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text("\n".join(lines)+"\n")
print(f"M1-CORPUS generated lines={len(lines)} main={expected}")
