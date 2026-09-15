# Setting up a Kotlin library with kotlin-ci-shared

Two paths: [A. New library](#a-new-library) or [B. Migrate an existing library](#b-migrate-an-existing-library).
Both end with the same [verification checklist](#verification-checklist).

Placeholders used below: `<repo>` = GitHub repo name (e.g. `statemachine-kt`),
`<module>` = Gradle module that is published (e.g. `statemachine`),
`<group>` = Maven group (e.g. `com.amine2233.statemachine`).

## Gradle requirements

The shared CI only assumes three things about the Gradle build:

1. **A committed Gradle wrapper** (`gradlew`, `gradle/wrapper/*`). All tasks call `./gradlew`.
2. **The version comes from `-Pversion`** — root `build.gradle.kts`:

   ```kotlin
   allprojects {
       group = "<group>"
       version = (findProperty("version") as String?)?.takeIf { it.isNotBlank() } ?: "0.1.0-SNAPSHOT"
   }
   ```

3. **The library module publishes to GitHub Packages** — `<module>/build.gradle.kts`:

   ```kotlin
   plugins {
       kotlin("jvm")
       `maven-publish`
   }

   java { withSourcesJar() }

   publishing {
       publications {
           create<MavenPublication>("gpr") {
               from(components["java"])
               groupId = project.group.toString()
               artifactId = "<module>"
               version = project.version.toString()
               pom {
                   name.set("<Module>")
                   description.set("...")
                   url.set("https://github.com/amine2233/<repo>")
                   licenses { license { name.set("MIT License"); url.set("https://opensource.org/licenses/MIT") } }
                   developers { developer { id.set("amine2233"); name.set("Amine Bensalah") } }
                   scm { url.set("https://github.com/amine2233/<repo>") }
               }
           }
       }
       repositories {
           maven {
               name = "GitHubPackages"
               url = uri("https://maven.pkg.github.com/amine2233/<repo>")
               credentials {
                   username = System.getenv("GITHUB_ACTOR")
                   password = System.getenv("GITHUB_TOKEN")
               }
           }
       }
   }
   ```

Optional plugins, only if you enable the matching feature:

| Feature | Plugin | Task it unlocks |
| --- | --- | --- |
| Coverage (`enable-coverage: true`) | `org.jetbrains.kotlinx.kover` | `mise run test-coverage` |
| Docs (`pages.yml`) | `org.jetbrains.dokka` | `mise run build_documentations` |

## A. New library

```bash
mkdir <repo> && cd <repo> && git init -b main
```

1. **Scaffold Gradle** — `gradle init --type kotlin-library --dsl kotlin` (or copy
   from an existing library), commit the wrapper, apply the
   [Gradle requirements](#gradle-requirements).
2. **Copy the templates** from this repo:

   ```bash
   CI=/path/to/kotlin-ci-shared
   cp $CI/templates/mise.toml           mise.toml
   cp $CI/templates/.releaserc.json     .releaserc.json
   cp $CI/templates/.env.local.example  .env.local.example
   mkdir -p .github/workflows
   cp $CI/examples/ci.yml $CI/examples/release.yml .github/workflows/
   # optional: cp $CI/examples/pages.yml .github/workflows/
   ```

   Nothing in `mise.toml` or `.releaserc.json` is project-specific — `publish`
   runs `./gradlew publish`, which publishes every module that applies
   `maven-publish`.
3. **Ignore local files** — add to `.gitignore`: `.gradle/`, `build/`, `.kotlin/`,
   `.idea/`, `*.iml`, `.env.local`, `node_modules/`.
4. **Local setup**:

   ```bash
   mise trust && mise install        # JDK, node, ktlint
   cp .env.local.example .env.local  # then fill GITHUB_ACTOR / GITHUB_TOKEN (write:packages)
   mise run lint && mise run test
   ```

5. **Create the GitHub repo** and push `main`. Then in the repo settings:
   - *Actions → General → Workflow permissions*: **Read and write permissions**.
   - Optional (Pages): *Pages → Source*: **GitHub Actions**.
   - Optional (protected `main`): see the
     [protected branch section in the README](../README.md#repo-setup-let-the-release-push-to-a-protected-main).
6. **First release**: merge a `feat:` commit into `main`. The `Release` workflow
   runs CI, then semantic-release computes the version, updates `CHANGELOG.md`,
   tags `vX.Y.Z`, publishes to GitHub Packages and creates the GitHub release
   with the jars attached.

## B. Migrate an existing library

Example: [`statemachine-kt`](https://github.com/amine2233/statemachine-kt),
which already has inlined workflows, a `mise.toml` with only `[tools]`, and a
`.releaserc.json` that calls `./gradlew :statemachine:publish` directly.

1. **Replace the workflows**:

   ```bash
   rm .github/workflows/ci.yml .github/workflows/release.yml
   cp $CI/examples/ci.yml $CI/examples/release.yml .github/workflows/
   ```

2. **Replace `mise.toml`** with `templates/mise.toml`. Keep any project-specific
   `[tools]` versions (e.g. a different JDK) — change the tool versions, not the
   task names.
3. **Replace `.releaserc.json`** with `templates/.releaserc.json`. The only
   behavioural change is `publishCmd`: `mise run publish --version X` instead of a
   hard-coded `./gradlew :<module>:publish`. If you must publish a single module
   only, edit the `publish` task in `mise.toml` (not `.releaserc.json`).
4. **Check the Gradle requirements** above — an existing library usually already
   satisfies them.
5. **Update the library README**: the CI/CD section should point to this repo,
   and the "Development" section to `mise run test` / `mise run lint`.
6. Run the [verification checklist](#verification-checklist), open a PR, watch
   the `CI` workflow go green, merge.

## Verification checklist

```bash
mise trust && mise install
mise tasks                     # lists: build build_documentations check_code check_merge_request_title format lint publish release test test-coverage
mise run lint                  # ktlint, must pass (run `mise run format` first on a legacy codebase)
mise run test                  # ./gradlew test
mise run release --dry-run     # needs GITHUB_TOKEN in .env.local; prints the next version or "no release"
```

Then push a branch, open a PR → the `CI` workflow shows `Lint`, `Test` (and
`Pull request title` if enabled). Merge → the `Release` workflow runs `CI` then
`Semantic Release`.

## Consuming a published library

GitHub Packages requires authentication even for public packages. In the
consumer's `build.gradle.kts`:

```kotlin
repositories {
    mavenCentral()
    maven {
        url = uri("https://maven.pkg.github.com/amine2233/<repo>")
        credentials {
            username = (findProperty("gpr.user") as String?) ?: System.getenv("GITHUB_ACTOR")
            password = (findProperty("gpr.key") as String?) ?: System.getenv("GITHUB_TOKEN")
        }
    }
}

dependencies {
    implementation("<group>:<module>:1.0.0")
}
```

`gpr.key` needs the `read:packages` scope. Put `gpr.user` / `gpr.key` in
`~/.gradle/gradle.properties`, never in the repo.

## Local commands cheat-sheet

| Command | What it does |
| --- | --- |
| `mise run test` | `./gradlew test` |
| `mise run build` | `./gradlew build` |
| `mise run format` | ktlint auto-format |
| `mise run lint` | ktlint check (what CI runs on PRs) |
| `mise run test-coverage` | tests + Kover report (needs the Kover plugin) |
| `mise run build_documentations` | Dokka HTML into `build/dokka/html` (needs the Dokka plugin) |
| `mise run publish --version 1.2.3` | publish to GitHub Packages (needs `.env.local`) |
| `mise run release --dry-run` | preview the next semantic-release version |
