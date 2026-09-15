# AI agent runbook: wire a Kotlin library to kotlin-ci-shared

Deterministic checklist for AI coding agents (Claude Code, Codex, Cursor, …).
Follow the steps in order. Do not improvise: every file to create is given in
full or by an exact copy command. Human-oriented explanations are in
[`SETUP.md`](SETUP.md).

`$CI` below = a local checkout of `amine2233/kotlin-ci-shared`. If it is not
available locally, clone it: `git clone https://github.com/amine2233/kotlin-ci-shared "$CI"`.

## 0. Detect the project state

Run from the library root and record the answers:

| Check | Command | Expected |
| --- | --- | --- |
| Gradle wrapper committed | `test -x gradlew && test -f gradle/wrapper/gradle-wrapper.properties` | exit 0 — if not, STOP and ask the user to add the wrapper |
| Kotlin JVM build | `rg -l 'kotlin\("jvm"\)|kotlin-jvm|org.jetbrains.kotlin.jvm' -g '*.gradle.kts' -g '*.toml'` | ≥ 1 file |
| Published module(s) | `rg -l 'maven-publish' -g '*.gradle.kts'` | ≥ 1 file (module dirs = `<module>`) |
| GitHub Packages repository block | `rg -n 'maven.pkg.github.com' -g '*.gradle.kts'` | ≥ 1 match |
| Version from `-Pversion` | `rg -n 'findProperty\("version"\)' build.gradle.kts` | ≥ 1 match |
| Existing `mise.toml` | `test -f mise.toml` | either |
| Existing workflows | `ls .github/workflows/` | either |
| Existing `.releaserc.json` | `test -f .releaserc.json` | either |
| Repo slug | `git remote get-url origin` | `amine2233/<repo>` |

## 1. Fix the Gradle build (only for rows that failed in step 0)

- **No `maven-publish` block** → add the `plugins { \`maven-publish\` }`,
  `java { withSourcesJar() }` and `publishing { … }` block from
  [`SETUP.md` → Gradle requirements](SETUP.md#gradle-requirements) to
  `<module>/build.gradle.kts`, replacing `<module>`, `<repo>`, `<Module>`.
- **No `-Pversion` handling** → in root `build.gradle.kts` add inside `allprojects { }`:
  `version = (findProperty("version") as String?)?.takeIf { it.isNotBlank() } ?: "0.1.0-SNAPSHOT"`.
- Do NOT add signing, Sonatype/Maven Central, vanniktech, or any lint Gradle plugin.

## 2. Copy the templates (overwrite)

```bash
cp "$CI/templates/mise.toml"          mise.toml
cp "$CI/templates/.releaserc.json"    .releaserc.json
cp "$CI/templates/.env.local.example" .env.local.example
```

Then, only if the previous `mise.toml` pinned different `[tools]` versions
(e.g. `java = "temurin-21"`), re-apply those version values in the new
`mise.toml`. Never rename or remove a `[tasks.*]` entry.

## 3. Copy the workflows (overwrite)

```bash
mkdir -p .github/workflows
rm -f .github/workflows/ci.yml .github/workflows/release.yml .github/workflows/publish.yml
cp "$CI/examples/ci.yml"      .github/workflows/ci.yml
cp "$CI/examples/release.yml" .github/workflows/release.yml
```

Only if the user asked for hosted docs AND `org.jetbrains.dokka` is applied in
the build: `cp "$CI/examples/pages.yml" .github/workflows/pages.yml`.

Do not edit the `uses:` refs; `@main` (or the pinned version present in the
example) is intentional.

## 4. `.gitignore`

Ensure each of these lines is present (append missing ones):

```
.gradle/
build/
.kotlin/
.idea/
*.iml
.DS_Store
.env.local
node_modules/
```

## 5. Verify locally

```bash
mise trust && mise install
mise tasks | awk '{print $1}' | sort | tr '\n' ' '
# expected: build build_documentations check_code check_merge_request_title format lint publish release test test-coverage
mise run lint
mise run test
```

- If `mise run lint` fails on a pre-existing codebase: run `mise run format`,
  re-run `mise run lint`, and include the formatting changes in a separate
  `style:` commit. Errors that survive `format` (typically `standard:kdoc`,
  `no-consecutive-comments`) must be fixed by hand in the reported files.
- `mise run release --dry-run` needs the local `main` in sync with the remote
  (`git fetch --tags --force && git pull --ff-only`) or it reports
  "local branch main is behind" / "would clobber existing tag".
- `mise run release --dry-run` requires `GITHUB_TOKEN`; skip it if `.env.local`
  is absent and tell the user.

## 6. Update the library README

Replace/insert a "CI/CD" section with this text (adapt `<repo>` and `<module>`):

```markdown
## CI/CD

CI and releases come from [kotlin-ci-shared](https://github.com/amine2233/kotlin-ci-shared).
All logic lives in `mise.toml`:

- `mise run test` / `mise run lint` — what the `CI` workflow runs on pull requests.
- Merging a `feat:` / `fix:` commit into `main` runs semantic-release: it tags
  `vX.Y.Z`, updates `CHANGELOG.md`, publishes `<group>:<module>` to GitHub
  Packages and creates the GitHub release with the jars attached.
- `mise run release --dry-run` previews the next version locally.
```

Remove any stale statements (e.g. "CI installs Gradle X directly", references to
`publish.yml`, manual version inputs).

## 7. Commit

One conventional commit, e.g.:

```
ci: use amine2233/kotlin-ci-shared workflows
```

Do not push unless the user asked.

## 8. Report to the user

List: files added/replaced, Gradle changes (if any), local check results, and
the one-time GitHub settings the user must do themselves:

- *Settings → Actions → General → Workflow permissions* = **Read and write**.
- Pages only: *Settings → Pages → Source* = **GitHub Actions**.
- Protected `main` only: add a bypass actor or a `RELEASE_TOKEN` secret
  (README → "Repo setup: let the release push to a protected `main`").

## Acceptance criteria

- `mise tasks` lists the 10 task names above.
- `mise run lint` and `mise run test` exit 0.
- `.github/workflows/ci.yml` and `release.yml` are byte-identical to
  `$CI/examples/ci.yml` and `$CI/examples/release.yml` (unless the user asked
  for a customisation).
- `.releaserc.json` `publishCmd` is `mise run publish --version ${nextRelease.version}`.
- No new Gradle plugins were added except Kover/Dokka when explicitly requested.

## Do not

- Do not change `tagFormat` in the library's `.releaserc.json` (libraries keep `v1.2.3`).
- Do not add signing / Maven Central.
- Do not inline Gradle commands into workflow YAML — put them in `mise.toml` tasks.
- Do not add macOS/Windows runners.
- Do not add `actions/setup-java`; the JDK comes from `mise.toml`.
