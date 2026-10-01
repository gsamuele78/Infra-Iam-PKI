# Makefile — Infra-IAM-PKI developer entry points.
# Targets are honest: `test` fails until the tests exist (ALIGNMENT-PLAN Phase 5).
# RSTUDIOCONF_SOURCE overrides where the vendor check fetches R-studioConf from
# (e.g. a local checkout while an upstream branch is not pushed yet).

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.PHONY: help lint validate test agents hooks vendor-check

STACKS := infra-pki infra-iam infra-ood infra-rstudio
RSTUDIOCONF_SOURCE ?=

help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## //'

## lint          shellcheck (non-vendored scripts), validate.sh, generate.sh --check, vendor check
lint: vendor-check
	@lock=infra-rstudio/UPSTREAM.lock; \
	vendored=$$( { jq -r '.mappings[] | select(.files == null) | .to' "$$lock" | while read -r d; do git ls-files "$$d/*.sh"; done; \
	               jq -r '.mappings[] | select(.files != null) | .to as $$t | .files[] | "\($$t)/\(.)"' "$$lock"; } | sort -u ); \
	git ls-files -c -o --exclude-standard '*.sh' | sort -u | comm -23 - <(printf '%s\n' "$$vendored") | xargs shellcheck -x -S warning
	.ai/validate.sh --ci
	.ai/generate.sh --check

## vendor-check  vendored RStudio trees equal R-studioConf at the pinned commit
vendor-check:
	scripts/infra-rstudio/sync_rstudioconf.sh --check $(if $(RSTUDIOCONF_SOURCE),--source $(RSTUDIOCONF_SOURCE))

## validate      docker compose config for the four stacks and the sandbox overrides
validate:
	@for s in $(STACKS); do \
	  env=.env.sandbox; [ -f "$$s/$$env" ] || env=.env.example; \
	  echo "compose config: $$s ($$env)"; \
	  (cd "$$s" && docker compose --env-file "$$env" config -q); \
	done
	@for f in sandbox/*-sandbox.yml; do echo "compose config: $$f"; docker compose -f "$$f" config -q; done

## test          not implemented yet: exits 1 so nothing pretends to pass
test:
	@echo "No automated tests yet: see doc/plan/ALIGNMENT-PLAN.md Phase 5." >&2; exit 1

## agents        regenerate CLAUDE.md, AGENTS.md and the other agent files
agents:
	.ai/generate.sh

## hooks         install the pre-commit hook
hooks:
	.ai/install-hooks.sh
