# AI Agent Management & Extrapolability

To maintain the strict "Pessimistic System Engineering" architecture over the lifecycle of the `Infra-IAM-PKI` project, this codebase actively manages the context and constraints of AI coding assistants (Claude, Cursor, Copilot, etc.).

## Architecture

The AI management system lives in two directories:

- `.ai/`: Contains the constraint definitions (`project.yml`) and the compiler scripts (`generate.sh`, `validate.sh`).
- `.agents/`: Contains highly specialized "Skills" (checklists and logic) for agents executing specific high-risk tasks.

## The Constraint Enforcer (`.ai/validate.sh`)

Before any code is committed or deployed, `.ai/validate.sh` scans the actual codebase against the project's hard constraints (HC-01 through HC-14). It statically analyzes Docker Compose configurations, Bash scripts, and HTML/CSS templates for violations of pessimistic design (e.g., missing resource limits, optimistic `set -e` usage instead of `set -euo pipefail`, exposed database ports, implicit dependencies).

## Agent Rules Generation (`.ai/generate.sh`)

Rather than maintaining separate rule files for every AI tool, `.ai/project.yml` serves as the single source of truth. Running `.ai/generate.sh` performs two actions:

1. **Codebase Scanning**: It extracts live data from the code (e.g., pinning exact image versions found in `docker-compose.yml`, counting `.env` variables).
2. **Context Compilation**: It merges the hard constraints with the live data and compiles customized rule files (`.clinerules`, `.cursorrules`, `CLAUDE.md`, `.github/copilot-instructions.md`).

This ensures that whenever an AI agent reads the repository, it is immediately bound by the same pessimistic engineering constraints as human system engineers.

## Agent Skills (`.agents/skills/`)

When an agent needs to perform a complex routine (like fixing a compose file or auditing a script), it is instructed to read a corresponding `SKILL.md` file. These skills contain manual checklists that translate abstract constraints into step-by-step verification flows.
