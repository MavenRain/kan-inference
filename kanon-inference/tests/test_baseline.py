"""Independent parser/ranking cases, separate from the authored diagnostic corpus."""

import importlib.util
from pathlib import Path
import unittest


SPEC = importlib.util.spec_from_file_location("baseline", Path(__file__).resolve().parents[1] / "baseline.py")
baseline = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(baseline)


class BaselineTests(unittest.TestCase):
    def rank(self, hint, expected_type, candidates, **extra):
        return baseline.rank_candidates(dict(hint=hint, expected_type=expected_type, candidates=candidates, **extra))

    def test_novel_constant_and_folded_expression(self):
        candidates = ["42", "natAdd 400 17", "417", "natSub 417 1"]
        self.assertEqual(self.rank("Return 417.", "Nat", candidates), [candidates[1], candidates[2], candidates[0], candidates[3]])

    def test_identifier_renaming_and_alpha_equivalence(self):
        for names in (("x", "y"), ("parcel", "slot"), ("a_9", "b_2")):
            first, second = names
            expected_type = f"({first} : Nat) -> ({second} : Nat) -> Nat"
            wrong = f"fun ({first} : Nat) ({second} : Nat) => {first}"
            right = "fun (fresh : Nat) (renamed : Nat) => renamed"
            self.assertEqual(self.rank(f"Return {second}.", expected_type, [wrong, right]), [right, wrong])

    def test_third_and_last_argument(self):
        candidates = ["fun (a : Nat) (b : Nat) (c : Nat) => b", "fun (a : Nat) (b : Nat) (c : Nat) => c"]
        expected_type = "(u : Nat) -> (v : Nat) -> (w : Nat) -> Nat"
        for hint in ("Return the third argument.", "Return the last argument."):
            self.assertEqual(self.rank(hint, expected_type, candidates), candidates[::-1])

    def test_addition_and_multiplication_structure(self):
        candidates = ["fun (a : Nat) => natAdd a 2", "fun (a : Nat) => natAdd a a", "fun (a : Nat) => natMul 2 a"]
        self.assertEqual(self.rank("Double the input.", "(value : Nat) -> Nat", candidates), [candidates[1], candidates[2], candidates[0]])

    def test_distributivity_and_stable_ties(self):
        candidates = [
            "fun (a : Nat) (b : Nat) => natAdd (natMul a a) (natMul b b)",
            "fun (a : Nat) (b : Nat) => natMul (natAdd a b) 17",
            "fun (a : Nat) (b : Nat) => natAdd (natMul 17 a) (natMul b 17)",
        ]
        ranked = self.rank("Multiply the sum of the arguments by 17.", "(x : Nat) -> (y : Nat) -> Nat", candidates)
        self.assertEqual(ranked, [candidates[1], candidates[2], candidates[0]])

    def test_nested_affine_expression_novel_factor(self):
        candidates = ["fun (a : Nat) (b : Nat) => natAdd (natMul 13 a) b", "fun (a : Nat) (b : Nat) => natAdd (natMul b 13) a"]
        self.assertEqual(self.rank("Return the first argument plus 13 times the second argument.", "(x : Nat) -> (y : Nat) -> Nat", candidates), candidates[::-1])

    def test_truncated_subtraction_direction(self):
        candidates = ["fun (n : Nat) => natSub n 23", "fun (n : Nat) => natSub 23 n"]
        self.assertEqual(self.rank("Subtract the input from 23.", "(n : Nat) -> Nat", candidates), candidates[::-1])
        self.assertEqual(self.rank("Return zero.", "Nat", ["1", "natSub 3 91"]), ["natSub 3 91", "1"])

    def test_subtraction_is_not_commutative(self):
        candidates = ["fun (x : Nat) (y : Nat) => natSub y x", "fun (x : Nat) (y : Nat) => natSub x y"]
        self.assertEqual(self.rank("Subtract the second argument from the first argument.", "(x : Nat) -> (y : Nat) -> Nat", candidates), candidates[::-1])

    def test_zero_and_one_identities(self):
        candidates = ["fun (v : Nat) => natAdd v 1", "fun (v : Nat) => natMul (natSub v 0) 1"]
        self.assertEqual(self.rank("Return the input unchanged.", "(n : Nat) -> Nat", candidates), candidates[::-1])

    def test_unknown_hint_or_suffix_preserves_order(self):
        candidates = ["9", "7", "natAdd 3 4"]
        for hint in ("Compute something useful.", "Return seven unless it rains.", "Return seven or nine."):
            self.assertEqual(self.rank(hint, "Nat", candidates), candidates)

    def test_no_matching_structure_preserves_order(self):
        candidates = ["2", "3", "4"]
        self.assertEqual(self.rank("Return 97.", "Nat", candidates), candidates)

    def test_unsupported_type_and_free_names_preserve_order(self):
        candidates = ["helper", "fun (n : Nat) => n"]
        self.assertEqual(self.rank("Return the input unchanged.", "Nat -> Nat", candidates), candidates)
        candidates = ["fun (n : Nat) => missing", "fun (n : Nat) => natAdd n 1"]
        self.assertEqual(self.rank("Return the input unchanged.", "(n : Nat) -> Nat", candidates), candidates)

    def test_unsupported_or_malformed_candidate_is_not_executed(self):
        candidates = ["__import__('os').system('false')", "natAdd 7", "(7", "7 def evil : Nat := 0", "7"]
        self.assertEqual(self.rank("Return seven.", "Nat", candidates), ["7", *candidates[:-1]])

    def test_duplicate_candidates_and_original_list_are_preserved(self):
        candidates = ["1", "7", "1", "7"]
        self.assertEqual(self.rank("Return seven.", "Nat", candidates), ["7", "7", "1", "1"])
        self.assertEqual(candidates, ["1", "7", "1", "7"])

    def test_oracle_and_task_metadata_do_not_affect_ranking(self):
        candidates = ["3", "7"]
        ordinary = self.rank("Return seven.", "Nat", candidates)
        tainted = self.rank("Return seven.", "Nat", candidates, id="pick_three", expected=3,
                            tests=[{"arguments": [], "expected": 3}], context="def three : Nat := 3")
        self.assertEqual(ordinary, tainted)

    def test_oversized_and_deep_expressions_preserve_other_candidates(self):
        candidates = ["9" * 100, "(" * 80 + "7" + ")" * 80, "7"]
        self.assertEqual(self.rank("Return seven.", "Nat", candidates), ["7", *candidates[:-1]])


if __name__ == "__main__":
    unittest.main()
