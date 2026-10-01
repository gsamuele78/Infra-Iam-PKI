# Makefile — Infra-IAM-PKI developer entry points.
# CI (.github/workflows/lint.yml) runs these same targets, one job each, so
# `make lint` locally is exactly the lint CI. Targets are honest: `test` fails
# until the tests exist (ALIGNMENT-PLAN Phase 5).
#
# RSTUDIOCONF_SOURCE overrides where vendor-check fetches R-studioConf from
# (e.g. a local checkout while an upstream branch is not pushed yet).

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.PHONY: help lint shellcheck constraints agents-check vendor-check yamllint hadolint markdownlint \
        validate test agents hooks

STACKS := infra-pki infra-iam infra-ood infra-rstudio
LOCK := infra-rstudio/UPSTREAM.lock
RSTUDIOCONF_SOURCE ?=
YAMLLINT ?= $(shell command -v yamllint >/dev/null 2>&1 && echo yamllint || echo "uvx yamllint")
HADOLINT ?= hadolint
MARKDOWNLINT ?= npx -y markdownlint-cli2@0.23.3

# Vendored RStudio paths are linted by R-studioConf's own gates; integrity is vendor-check.
# Whole-tree mappings come from the lock, so a new mapping is excluded automatically.
VENDORED_RE := $(shell jq -r '[.mappings[] | select(.files == null) | "^" + .to + "/"] | join("|")' $(LOCK))
MD_EXCLUDES := '!infra-rstudio/**' '!kubernetes-deploy/rstudio/**' '!**/node_modules/**' \
               '!sandbox/.vagrant/**' '!.serena/**' '!.omo/**' '!CLAUDE.md' '!.github/copilot-instructions.md'

help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## //'

## lint          every lint job CI runs
lint: shellcheck constraints agents-check vendor-check yamllint hadolint markdownlint

## shellcheck    shellcheck -x on every non-vendored script
shellcheck:
	@listed=$$(jq -r '.mappings[] | select(.files != null) | .to as $$t | .files[] | "\($$t)/\(.)"' $(LOCK) | sort -u); \
	git ls-files -c -o --exclude-standard '*.sh' | sort -u | grep -vE '$(VENDORED_RE)' \
	  | comm -23 - <(printf '%s\n' "$$listed") | xargs shellcheck -x -S warning

## constraints   .ai/validate.sh (the 14 hard rules)
constraints:
	.ai/validate.sh --ci --fix-hint

## agents-check  generated agent files (CLAUDE.md, AGENTS.md, ...) are up to date
agents-check:
	.ai/generate.sh --check

## vendor-check  vendored RStudio trees equal R-studioConf at the pinned commit
vendor-check:
	scripts/infra-rstudio/sync_rstudioconf.sh --check $(if $(RSTUDIOCONF_SOURCE),--source $(RSTUDIOCONF_SOURCE))

## yamllint      YAML style (tests/lint/.yamllint.yml)
yamllint:
	$(YAMLLINT) -c tests/lint/.yamllint.yml .

## hadolint      every non-vendored Dockerfile
hadolint:
	@git ls-files -c -o --exclude-standard | grep -E '(^|/)Dockerfile[^/]*$$' \
	  | grep -vE '$(VENDORED_RE)' | xargs $(HADOLINT) --config tests/lint/.hadolint.yaml

## markdownlint  every non-vendored, non-generated Markdown file
markdownlint:
	$(MARKDOWNLINT) --config tests/lint/.markdownlint.yaml '**/*.md' $(MD_EXCLUDES)

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
