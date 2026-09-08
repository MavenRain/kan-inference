PYTHON ?= python3
COMPILER := $(CURDIR)/kanon-synth/_build/default/bin/kanon.exe
CORPUS := kanon-inference/benchmarks/diagnostic-v1.json
BENCHMARK := kanon-inference/benchmark.py
HOSTS ?= kernel
OUTPUT ?= kanon-inference/results/local/diagnostic.json
SPLIT ?=
require_split = $(if $(SPLIT),,$(error Set SPLIT=train|validation|test))
CHALLENGE_CORPUS := kanon-inference/benchmarks/challenge-v1.json
CHALLENGE_SPLITS := kanon-inference/benchmarks/challenge-v1.splits.json
CHALLENGE_OUTPUT ?= kanon-inference/results/local/challenge-$(SPLIT).json
EXPERIMENT_PLAN ?= kanon-inference/experiments/challenge-prompts-v1.json
EXPERIMENT_OUTPUT ?= kanon-inference/results/local/challenge-prompts-v1
SELECTION ?=
FROZEN_OUTPUT ?= kanon-inference/results/local/challenge-frozen-test.json

.PHONY: build test test-all test-unit test-provider benchmark-baseline benchmark-135m benchmark-challenge-baseline benchmark-challenge-135m
.PHONY: experiment-challenge experiment-test

build:
	cd kanon-synth && dune build bin/kanon.exe test/synthesis.exe

test-unit:
	$(PYTHON) -m unittest discover -s kanon-inference/tests -p 'test_*.py'

test:
	test -x "$(COMPILER)" || { echo "Build the compiler first: make build" >&2; exit 1; }
	$(MAKE) test-unit
	./kanon-synth/_build/default/test/synthesis.exe
	KANON_TEST_COMPILER="$(COMPILER)" $(PYTHON) kanon-synth/dev/test_synth.py

test-provider:
	./kanon-inference/.venv/bin/python -I kanon-inference/test_protocol.py

# test-provider needs the local provider virtual environment; plain test does not.
test-all:
	$(MAKE) test
	$(MAKE) test-provider

benchmark-baseline:
	$(PYTHON) $(BENCHMARK) --compiler "$(COMPILER)" --corpus $(CORPUS) --hosts $(HOSTS) --output "$(OUTPUT)"

benchmark-135m:
	$(PYTHON) $(BENCHMARK) --compiler "$(COMPILER)" --corpus $(CORPUS) --hosts $(HOSTS) --provider kanon-inference/provider --output "$(OUTPUT)"

benchmark-challenge-baseline:
	$(require_split)$(PYTHON) $(BENCHMARK) --compiler "$(COMPILER)" --corpus "$(CHALLENGE_CORPUS)" --split-manifest "$(CHALLENGE_SPLITS)" --split "$(SPLIT)" --hosts $(HOSTS) --output "$(CHALLENGE_OUTPUT)"

benchmark-challenge-135m:
	$(require_split)$(PYTHON) $(BENCHMARK) --compiler "$(COMPILER)" --corpus "$(CHALLENGE_CORPUS)" --split-manifest "$(CHALLENGE_SPLITS)" --split "$(SPLIT)" --hosts $(HOSTS) --provider kanon-inference/provider --output "$(CHALLENGE_OUTPUT)"

experiment-challenge:
	$(PYTHON) kanon-inference/experiment.py run --plan "$(EXPERIMENT_PLAN)" --compiler "$(COMPILER)" --output-dir "$(EXPERIMENT_OUTPUT)"

experiment-test:
	$(if $(SELECTION),,$(error Set SELECTION=path/to/selection.json))$(PYTHON) kanon-inference/experiment.py test --selection "$(SELECTION)" --output "$(FROZEN_OUTPUT)"
