# AGENTS.md

This repo is the shared GitHub Actions CI for `amine2233` Kotlin/Gradle
libraries: reusable workflows (`.github/workflows/`), one composite action
(`actions/gradle-run`), templates to copy into libraries (`templates/`) and
example caller workflows (`examples/`).

- To wire a **library repo** to this CI, follow [`docs/AI-SETUP.md`](docs/AI-SETUP.md) step by step.
- To change **this repo**: workflows never contain build logic — they only call
  `mise run <task>`. The task-name contract consumers rely on is
  `test`, `test-coverage`, `build`, `format`, `check_code`, `lint`,
  `check_merge_request_title`, `build_documentations`, `publish`, `release`
  (defined in `templates/mise.toml`). Renaming one is a breaking change.
- Refs in `README.md`, `docs/` and `examples/` are rewritten by `bumpversion.sh`
  on release; leave `@main` / pinned versions as they are.
- Releases of this repo are manual (`Release` workflow, `workflow_dispatch`);
  commits follow Conventional Commits.
