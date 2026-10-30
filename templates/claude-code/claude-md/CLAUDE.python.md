# Project: <PACKAGE NAME> (copy to ./CLAUDE.md)

<What this package/service does, in one or two sentences.>

## Environment
- Python <3.12+>, managed with <uv | poetry | venv + pip>
- Activate: `source .venv/bin/activate` (Windows WSL: same)
- Never install packages globally; add them to `pyproject.toml`.

## Commands
- Install: `uv sync` (or `pip install -e ".[dev]"`)
- Tests: `pytest -q` (single test: `pytest -q tests/test_x.py::test_name`)
- Lint + format: `ruff check . && ruff format .`
- Types: `mypy src/`

## Definition of done
- `ruff check .`, `mypy src/`, and `pytest -q` pass.
- Public functions have type hints and a one-line docstring.

## Conventions
- `src/<package>/` layout. No code at import time beyond constants.
- Use `pathlib`, f-strings, and `logging` (not `print`) in library code.
- Data files in `data/` are read-only inputs; write outputs to `out/` (gitignored).

## Do not touch
- `.env`, `secrets/`, `data/raw/`, and notebooks in `archive/`.
