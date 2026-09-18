# kotlin-ci-shared

Shared [GitHub Actions](https://docs.github.com/actions) for Kotlin/Gradle
library development, consumed from any library repo
(e.g. [`statemachine-kt`](https://github.com/amine2233/statemachine-kt)).
Sibling of [`ci-shared`](https://github.com/amine2233/ci-shared) (Swift).

**The CI does not re-implement build/test/docs/release scripts.** Every project
ships a [`mise.toml`](https://mise.jdx.dev) whose tasks already encode that
logic. The shared workflows just install mise (JDK, node, ktlint), set up the
Gradle cache and run `mise run <task>`. One source of truth: the project's
`mise.toml`.

```
   consumer mise.toml               kotlin-ci-shared                       runner
   ────────────────                 ────────────────                       ──────
   [tasks.test]            ◀──── mise run test            ◀──── actions/gradle-run (mise-action + setup-gradle + mise run)
   [tasks.lint]            ◀──── mise run lint            ◀──── .github/workflows/ci.yml
   [tasks.build_documentations] ◀ mise run build_docu…    ◀──── .github/workflows/pages.yml
   [tasks.release]         ◀──── mise run release         ◀──── .github/workflows/semantic-release.yml
      └─ .releaserc.json ──▶ mise run publish --version X.Y.Z ──▶ GitHub Packages
```

## Setup a consumer repo

Step-by-step guides: [`docs/SETUP.md`](docs/SETUP.md) (humans) and
[`docs/AI-SETUP.md`](docs/AI-SETUP.md) (AI agents). Short version:

1. Copy [`templates/mise.toml`](templates/mise.toml) → `mise.toml`,
   [`templates/.releaserc.json`](templates/.releaserc.json) → `.releaserc.json`,
   [`templates/.env.local.example`](templates/.env.local.example) → `.env.local.example`.
   Keep the task **names** (`test`, `lint`, `publish`, `release`, …) so the
   workflows keep working.
2. Copy the workflows you want from [`examples/`](examples/) into
   `.github/workflows/`.
3. Make sure the library module has a `maven-publish` block targeting GitHub
   Packages and reads its version from `-Pversion` (see [`docs/SETUP.md`](docs/SETUP.md#gradle-requirements)).
4. For Pages: **Settings → Pages → Source = "GitHub Actions"**.

> Pin to a tag (`@1`, `@1.2` or `@1.2.3`) instead of `@main` once this repo is released.

## Building blocks

### Composite action — [`actions/gradle-run`](actions/gradle-run)

Installs mise (provisioning the `[tools]` from `mise.toml`, with caching via
[`jdx/mise-action`](https://github.com/jdx/mise-action)), sets up the Gradle
cache via [`gradle/actions/setup-gradle`](https://github.com/gradle/actions)
and runs one or more tasks. Use it directly when you want your own job layout.

| Input | Default | Description |
| --- | --- | --- |
| `tasks` | — (required) | Argument string for `mise run` (e.g. `test`, or `publish --version 1.2.3`). Chain several with ` ::: `. |
| `install-tools` | `true` | Install tools from `mise.toml` first |
| `mise-version` | `""` | Pin a mise version (empty = latest) |
| `cache` | `true` | Cache mise-installed tools |
| `gradle-cache-read-only` | `false` | Read the Gradle cache without writing it (use on PR/lint jobs) |
| `working-directory` | `.` | Where `mise.toml` lives / tasks run |
| `env` | `""` | `KEY=VALUE` lines exported before the task (used to pass `GITHUB_TOKEN`, etc.) |

```yaml
- uses: actions/checkout@v4
- uses: amine2233/kotlin-ci-shared/actions/gradle-run@1.0.1
  with:
    tasks: "test"
```

### Reusable workflows

| Workflow | File | Runs |
| --- | --- | --- |
| **CI** | [`ci.yml`](.github/workflows/ci.yml) | `mise run lint` (PRs) + `mise run test` (coverage optional) + reports artifact |
| **Semantic Release** | [`semantic-release.yml`](.github/workflows/semantic-release.yml) | `mise run release` on full git history → tag, changelog, GitHub Packages, GitHub release |
| **Pages** | [`pages.yml`](.github/workflows/pages.yml) | `mise run build_documentations` → upload `build/dokka/html` → deploy to Pages |

#### CI

```yaml
jobs:
  ci:
    uses: amine2233/kotlin-ci-shared/.github/workflows/ci.yml@1.0.1
    with:
      enable-coverage: false
```

| Input | Default | Description |
| --- | --- | --- |
| `runner` | `ubuntu-latest` | Runner image |
| `enable-lint` | `true` | Run the lint job (pull requests only) |
| `lint-task` | `lint` | mise task(s) for the lint job |
| `test-task` | `test` | mise task for tests |
| `enable-coverage` | `false` | Use `coverage-task` instead of `test-task` |
| `coverage-task` | `test-coverage` | mise task for coverage (needs the Kover plugin) |
| `upload-reports` | `true` | Upload `**/build/reports/{tests,kover}` as the `reports` artifact |
| `enable-title-check` | `false` | Check the PR title follows Conventional Commits (pull requests only) |
| `title-check-task` | `check_merge_request_title` | mise task for the title check (gets `PR_TITLE`) |

#### Semantic Release

```yaml
jobs:
  release:
    permissions:
      contents: write
      packages: write
      issues: write
      pull-requests: write
    uses: amine2233/kotlin-ci-shared/.github/workflows/semantic-release.yml@1.0.1
    secrets: inherit
```

| Input | Default | Description |
| --- | --- | --- |
| `release-task` | `release` | mise task that runs the release |
| `release-args` | `""` | Extra args (e.g. `--dry-run`) |
| `runner` | `ubuntu-latest` | Runner image |

The workflow exports `GITHUB_TOKEN` / `GH_TOKEN` (from `secrets: inherit`) and
`GITHUB_ACTOR` into the task environment; the consumer's `maven-publish`
credentials block reads those two variables. The `publish` step is not in the
workflow — it is the `publishCmd` of `@semantic-release/exec` in the consumer's
`.releaserc.json`, so `mise run release --dry-run` locally previews exactly
what CI will do.

Library tags keep semantic-release's default `v1.2.3` format (this repo itself
uses bare `1.2.3` so it can be pinned as `@1`).

#### Pages

```yaml
permissions:
  contents: read
  pages: write
  id-token: write
jobs:
  docs:
    uses: amine2233/kotlin-ci-shared/.github/workflows/pages.yml@1.0.1
```

| Input | Default | Description |
| --- | --- | --- |
| `runner` | `ubuntu-latest` | Runner image |
| `docs-task` | `build_documentations` | mise task building the docs (Dokka) |
| `output-path` | `build/dokka/html` | Directory the task writes into |

##### Repo setup: let the release push to a protected `main`

semantic-release commits `CHANGELOG.md` **back to the release branch** and
pushes tags. If `main` is protected (require a pull request, or "do not allow
bypassing"), the push is rejected:

```
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote: - Changes must be made through a pull request.
 ! [remote rejected] HEAD -> main (protected branch hook declined)
```

The default `GITHUB_TOKEN` (acting as `github-actions[bot]`) **cannot** bypass a
"require pull request" rule. Pick one:

1. **Add a bypass actor (recommended).** In the branch ruleset/protection for
   `main`, add the identity that runs the release to the bypass list:
   - **Rulesets** (*Settings → Rules → Rulesets → your `main` ruleset →
     Bypass list*): add **Repository admin**, or the GitHub App / user whose
     token you use below.
   - **Classic protection** (*Settings → Branches → main*): enable
     **Allow specified actors to bypass required pull requests** and add that
     actor.
2. **Use a token that owns the bypass.** The built-in `GITHUB_TOKEN` can't be
   added to a bypass list, so provide your own and pass it as `GH_TOKEN`:
   - a **fine-grained PAT** (or classic PAT with `repo` + `write:packages`)
     from an account in the bypass list, **or** a **GitHub App** installation
     token (recommended for orgs);
   - store it as a repo secret (e.g. `RELEASE_TOKEN`) and wire it in:

     ```yaml
     jobs:
       release:
         permissions:
           contents: write
           packages: write
           issues: write
           pull-requests: write
         uses: amine2233/kotlin-ci-shared/.github/workflows/semantic-release.yml@1.0.1
         secrets:
           GH_TOKEN: ${{ secrets.RELEASE_TOKEN }}
     ```

> The git identity is set via `GIT_AUTHOR_*` / `GIT_COMMITTER_*` env in the
> workflow, so the `Author identity unknown` error is already handled — this
> section is only about the **push permission**.

## Notes

- Composite actions run *inside the caller's job*, so the job provides the
  runner, `permissions`, and `actions/checkout`.
- Inside the reusable workflows the action is referenced by its full path on
  the `main` branch (not `./actions/...`): a relative `uses:` in a reusable
  workflow resolves against the *caller's* checkout.
- GitHub Packages is never anonymous: consumers of a published library need a
  token with `read:packages` even for public repos. Document that in the
  library README (see the consuming snippet in [`docs/SETUP.md`](docs/SETUP.md#consuming-a-published-library)).
- `ktlint` runs as a mise-installed binary, not a Gradle plugin: nothing to add
  to `build.gradle.kts`. Kover and Dokka *are* Gradle plugins and only needed
  when you turn on `enable-coverage` / the Pages workflow.

## Releasing kotlin-ci-shared itself

This repo versions itself with semantic-release so consumers can pin a stable
ref. The [`mise.toml`](mise.toml) defines a `semantic-release` task; the
[`Release`](.github/workflows/release.yml) workflow runs it:

- **Actions → Release → Run workflow** (optionally tick *dry-run* to preview).
- Or automatically on every push to `main`: set the repository variable
  `AUTO_RELEASE=true` (Settings → Secrets and variables → Actions → Variables).
  Same switch for consumers using [`examples/release.yml`](examples/release.yml).
- semantic-release (config in [`.releaserc.json`](.releaserc.json)) then:
  cuts a `X.Y.Z` tag (no `v` prefix) + GitHub release from Conventional Commits;
  pins the `amine2233/kotlin-ci-shared@<version>` refs in the README,
  [`docs/`](docs/) and [`examples/`](examples/) via [`bumpversion.sh`](bumpversion.sh);
  and moves the short tags `N` / `N.M` via [`post-release.sh`](post-release.sh)
  so callers can pin `@1` (latest 1.x) or `@1.2` (latest 1.2.x).

```bash
mise run semantic-release --dry-run   # preview locally
```

## Repository layout

```
templates/                   # copy into consumer repos: mise.toml (task contract), .releaserc.json, .env.local.example
examples/                    # caller workflows to copy into consumers
docs/SETUP.md                # human setup guide (new library / migrate an existing one)
docs/AI-SETUP.md             # deterministic setup checklist for AI agents
actions/gradle-run/          # composite action: mise + gradle cache + `mise run <task>`
.github/workflows/
  ci.yml semantic-release.yml pages.yml   # reusable workflows for consumers
  release.yml                             # manual workflow that releases kotlin-ci-shared itself
mise.toml                    # tasks for releasing THIS repo (semantic-release)
.releaserc.json              # semantic-release config for THIS repo
bumpversion.sh post-release.sh
```
