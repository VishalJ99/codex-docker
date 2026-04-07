# Agent Instructions

Reusable defaults for `codex-docker`. User-specific details belong in a private repo or local `AGENTS.md`.

## Host Networking

- **HOST SERVICES**: To reach services running on the host (e.g. vLLM, Jupyter, APIs), use `host.docker.internal` instead of `localhost` or `127.0.0.1`.
- **PORT INTERPRETATION**: When the user mentions `port 8000`, `localhost:8000`, or similar, translate to `http://host.docker.internal:8000`.
- **CURRENT HOST SERVICES**:
  - vLLM server: `http://host.docker.internal:8000/v1` (model: `Qwen/Qwen3-VL-8B-Instruct-FP8`)

## Python/Conda Path Resolution

- **MANDATORY CONDA BINARY**: Use `$CONDA_PREFIX/bin/conda` for conda operations when `CONDA_PREFIX` is set.
- **FALLBACK CONDA BINARY**: If `CONDA_PREFIX` is not set, use `${CONDA_EXE:-conda}`.
- **SCRIPT EXECUTION FORMAT**:
  1. List conda environments to resolve the Python binary path:
     - `${CONDA_EXE:-conda} env list`
     - `/vol/biomedic3/vj724/miniconda3/bin/conda env list`
  2. Run scripts with the direct interpreter path from the selected environment:
     - `/path/to/environment/bin/python your_script.py [args]`

## Decisions Log

- Each project should keep a `DECISIONS.md` file at the project root.
- `DECISIONS.md` is the canonical index and current-state summary for project taste, design choices, core assumptions, and the motivations behind why the system is architected the way it is.
- Do not leave important decisions only in chat, commits, or Linear tickets.
- When a meaningful decision is made or changed, update `DECISIONS.md` in the same task when practical.
- Prefer one source of truth per decision.
- If a project already has deeper design docs, ADRs, or a `docs/decisions/` directory, use `DECISIONS.md` as the top-level index and current-state summary, and link to the deeper record rather than duplicating the full decision in multiple places.

## Execution-Time Decisions

- After a prompt has been submitted, if implementation requires a decision that was not explicit in the prompt, record it in a separate pending-review section of `DECISIONS.md` and flag it in the final handoff.
- Once that decision has been explicitly discussed and agreed, move the agreed version into the main decisions section so accepted decisions live with the rest of the project's canonical choices.

## Linear

Use the Linear CLI for execution tracking, not as the architecture source of truth.
Relevant Linear issues should reference any ADR or contract doc they implement.

## Ticket Discipline

- Every substantive task should be mapped to a Linear issue.
- Before meaningful work, identify the active issue ID in commentary.
- If no suitable issue exists, create one before continuing.
- If a task touches multiple issues, use one primary issue and list secondary related issues.
- When scope changes materially, update the existing issue or create a follow-up issue.
- Keep issue status current as scope changes.
- When a task is complete, mark the issue as complete/Done.
- Do not leave completed work only in git history or chat without a corresponding Linear update.
