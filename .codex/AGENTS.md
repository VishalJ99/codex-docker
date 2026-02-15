# Default codex-docker user-level agent instructions.
# This file is copied to CODEX_DOCKER_HOME/codex-home/AGENTS.md only if one is not already present.

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
