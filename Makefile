# The one place the project's commands live. The docs point here, CI calls these
# targets, and `make` on its own lists them. `just` is not installed on CI.
#
# Overridable:
#   GODOT=/path/to/godot   the Godot 4.7 binary (default: godot on PATH)
#   PYTHON=python3.12      the interpreter (default: .venv/bin/python, else python3)
#   OUT=/tmp/shots         where `make capture` writes its PNGs
#   RUNS=5 FIGURES=1       rounds of `make perf`, and its standalone figure scenarios
#   WALKS=1                `make perf` also times the stress floor's people walking

GODOT ?= godot
PYTHON ?= $(shell [ -x .venv/bin/python ] && echo .venv/bin/python || echo python3)
GDLINT ?= $(shell [ -x .venv/bin/gdlint ] && echo .venv/bin/gdlint || echo gdlint)
GDFORMAT ?= $(shell [ -x .venv/bin/gdformat ] && echo .venv/bin/gdformat || echo gdformat)
OUT ?= build/captures
RUNS ?= 3
# The one test entry point, for `test` and for `check`.
RUN_TESTS = GODOT=$(GODOT) PYTHON=$(PYTHON) bash tools/run_tests.sh

# Every runtime art pack, by the directory it lives in (today only daylight).
PACKS := $(notdir $(patsubst %/manifest.json,%,$(wildcard assets/*/manifest.json)))

.DEFAULT_GOAL := help
.PHONY: help setup import imported run people people-templates people-skins wall-templates table-templates pixel-sources test test-art check check-scripts check-packs smoke docs-check lint fmt art capture walk-strips perf pack export clean

help:  ## List these targets
	@grep -hE '^[a-z][a-z-]*:.*##' $(MAKEFILE_LIST) \
		| sed -E 's/:.*## /\t/' \
		| awk -F'\t' '{printf "  \033[1m%-14s\033[0m %s\n", $$1, $$2}'

setup:  ## Create .venv and install the Python and lint tools
	python3 -m venv .venv
	.venv/bin/pip install -r tools/requirements-dev.txt

import:  ## Import the project (fills .godot/, needed after a fresh clone)
	GODOT=$(GODOT) bash tools/import_if_stale.sh --force

# Godot draws from its import cache, not from assets/: bring the cache up to
# date before a Godot run reads the project (tools/import_if_stale.sh; a no-op
# when nothing changed). tools/run_tests.sh, capture.sh and perf.sh ask it too.
imported:
	@GODOT=$(GODOT) bash tools/import_if_stale.sh

run:  ## Run the live office against your own herdr
	$(GODOT) --path .

test:  ## Every Godot test: script check, client, machines, incremental office
	$(RUN_TESTS)

test-art:  ## The three Python art contract tests (packs, table, pixel people)
	$(PYTHON) tools/test_assets.py -v
	$(PYTHON) tools/test_table_assets.py -v
	$(PYTHON) tools/test_pixel_people.py -v

# The tests run last, and without their own copy of check-scripts and
# check-packs: both have just run as prerequisites.
check: check-scripts check-packs lint docs-check test-art  ## What CI runs, in the order it runs it
	HERDSTEAD_SKIP_LOAD_CHECKS=1 $(RUN_TESTS)

check-scripts: imported  ## Prove every script and scene still loads
	$(GODOT) --headless --path . --script tools/check_scripts.gd

check-packs: imported  ## Prove every pack in assets/ still dresses the scenes
	$(GODOT) --headless --path . --script tools/check_packs.gd

# Godot exits 0 on a script error, so the log is the gate. No herdr, no saved
# machines and a private socket directory: nothing reaches the operator's own.
smoke: imported  ## Run the main scene once, headless and without herdr; fail on any script error
	@work="$$(mktemp -d)"; \
	HERDR_SOCKET_PATH=/nonexistent/herdr.sock HERDR_BIN_PATH="$$work/no-herdr" HERDSTEAD_SOCKET_DIR="$$work/socks" \
		$(GODOT) --headless --path . --quit >"$$work/run.log" 2>&1; \
	status=$$?; cat "$$work/run.log"; \
	if grep -qE 'SCRIPT ERROR|Parse Error' "$$work/run.log"; then echo "SMOKE_FAILED: a script error"; status=1; \
	elif ! grep -q '^OFFICE_START' "$$work/run.log"; then echo "SMOKE_FAILED: the office never started"; status=1; \
	elif [ "$$status" -eq 0 ]; then echo "SMOKE_OK"; fi; \
	rm -rf "$$work"; exit "$$status"

docs-check:  ## Every repo path and make target the entry docs name in backticks exists (tools/check_docs.py)
	$(PYTHON) tools/check_docs.py

lint:  ## gdlint (config in gdlintrc) and a gdformat check over scripts/ and tools/
	find scripts tools -name '*.gd' -print0 | xargs -0 $(GDLINT)
	$(GDFORMAT) --check --line-length=120 scripts tools

fmt:  ## Format scripts/ and tools/ the way `make lint` expects
	$(GDFORMAT) --line-length=120 scripts tools

art:  ## Rebuild assets/ from art/ and prove it matches the commit
	$(PYTHON) tools/build_assets.py
	$(PYTHON) tools/build_table_assets.py
	$(PYTHON) tools/build_pixel_people.py
	$(PYTHON) tools/check_build_clean.py assets

people:  ## Open the pixel people showroom: every agent, or every frame of one look (see scripts/people_showroom.gd for flags)
	$(GODOT) --path . scenes/people_showroom.tscn

people-templates: OUT = build/people-templates
people-templates:  ## Export pixel-people artist canvases, guide layers, sheets and the key-colour legend (OUT= an empty directory)
	$(PYTHON) tools/people_templates.py --output "$(abspath $(OUT))"

people-skins:  ## Check the pixel people's part skins, or cut new ones from a pixelized frame (CUT=<png> PARTS=head,torso, FACING=front, DROP=1, WEAR=hair_short)
	$(PYTHON) tools/people_skins.py $(if $(CUT),cut "$(abspath $(CUT))" --facing $(or $(FACING),front) --parts $(PARTS) --out art/pixel_people/skins/$(or $(FACING),front)$(if $(DROP), --drop-outside)$(if $(WEAR), --wear $(WEAR)),--check)

wall-templates: OUT = build/wall-templates
wall-templates:  ## Export matching wall corners, junctions and ends (OUT= an empty directory)
	$(PYTHON) tools/wall_templates.py --pack art/daylight/pack.json --output "$(abspath $(OUT))"

table-templates: OUT = build/table-templates
table-templates:  ## Author fresh table/furniture PNGs and manifest (OUT= an empty directory; never run by art)
	$(PYTHON) tools/build_table_assets.py --source art/daylight --templates "$(abspath $(OUT))"

pixel-sources: OUT = build/pixel-sources
pixel-sources:  ## Draw the density-1 desk props, cats and table family into OUT= (an empty directory; never run by art)
	$(PYTHON) tools/draw_pixel_sources.py --source art/daylight --output "$(abspath $(OUT))"

capture:  ## Screenshot the showroom, office, agent list, building section and agent card (OUT= to change)
	GODOT=$(GODOT) PYTHON=$(PYTHON) bash tools/capture.sh $(OUT)

# Windowed, like capture: the office is fed snapshots, `--read-only`, with no
# herdr, no saved machines and a private socket directory.
walk-strips: OUT = build/walk-strips
walk-strips: imported  ## Frame strips of people walking, every 0.25 s at 2x and 4x (OUT= to change)
	@GODOT=$(GODOT) bash tools/wait_for_screen.sh
	@work="$$(mktemp -d /tmp/herdstead-strips.XXXXXX)"; \
	HERDR_SOCKET_PATH=/nonexistent/herdr.sock HERDR_BIN_PATH="$$work/no-herdr" HERDSTEAD_SOCKET_DIR="$$work/socks" \
		$(GODOT) --path . --script tools/capture_walks.gd -- --out="$(abspath $(OUT))" --work="$$work" >"$$work/run.log" 2>&1; \
	status=$$?; cat "$$work/run.log"; \
	if grep -qE 'SCRIPT ERROR|Parse Error' "$$work/run.log"; then echo "WALK_STRIPS_FAILED: a script error"; status=1; \
	elif ! grep -q '^WALK_STRIPS_OK' "$$work/run.log"; then echo "WALK_STRIPS_FAILED: did not finish"; status=1; fi; \
	rm -rf "$$work"; exit "$$status"

perf:  ## Windowed CPU, fps, nodes, draw calls and refresh cost vs fake herdr (RUNS=3, FIGURES=1, WALKS=1); not in check
	GODOT=$(GODOT) PYTHON=$(PYTHON) bash tools/perf.sh --runs=$(RUNS) $(if $(FIGURES),--figures) $(if $(WALKS),--walks)

pack:  ## Export the PCK and check that every pack shipped in it
	mkdir -p build && touch build/.gdignore
	$(GODOT) --headless --path . --export-pack "macOS" build/Herdstead.pck
	@for pack in $(PACKS); do \
		echo "== $$pack"; \
		(cd build && $(GODOT) --headless --main-pack Herdstead.pck \
			--script "$(CURDIR)/tools/check_pack.gd" -- \
			--pack=res://assets/$$pack/manifest.json) || exit 1; \
	done

export:  ## Export build/Herdstead.app and its zip (needs export templates)
	GODOT=$(GODOT) tools/export_macos.sh

clean:  ## Remove what the targets above write into build/
	rm -rf build/captures build/Herdstead.pck build/Herdstead.app build/Herdstead-macos.zip
