# Semantic Versioning

Every releasable artefact in this repository — container image, Helm chart, Python package, OCI chart artefact — carries the same SemVer 2.0.0 version, derived from a single source of truth: the top-level `VERSION` file.

## Component meanings

`MAJOR.MINOR.PATCH[-prerelease][+build]`

| Component | When to increment |
|---|---|
| **MAJOR** | Backwards-incompatible change to the CLI / env-var contract, Helm values schema, `/healthz`/`/readyz`/`/metrics` shape, audit-log keys, persona role names, or DORA event fields |
| **MINOR** | Backwards-compatible addition: new Helm value with a safe default, new optional env var, new metric, new persona, new example |
| **PATCH** | Bug fixes, security patches, dependency-only updates with no behaviour change |
| **Pre-release** | `-alpha.N`, `-beta.N`, `-rc.N` for staged rollouts |
| **Build metadata** | `+sha.<short>` for traceability (does not affect ordering) |

Pre-release tags **never** carry the `latest`, `<major>`, or `<major>.<minor>` rolling Docker tags.

## Single source of truth

```
VERSION                                       0.1.0   ← canonical
├─ container/pyproject.toml                   version = "0.1.0"
├─ charts/claude-mate-agent/Chart.yaml        version: 0.1.0
│                                             appVersion: "0.1.0"
└─ charts/claude-mate-agent/values.yaml       tag: "0.1.0"
```

Drift between any of these fails CI via `make version-check`.

## Bump a version

```bash
make release-tag NEW=patch         # 0.1.0 → 0.1.1
make release-tag NEW=minor         # 0.1.0 → 0.2.0
make release-tag NEW=major         # 0.1.0 → 1.0.0
make release-tag NEW=1.4.0-rc.1    # exact SemVer string
```

This updates every dependent file atomically. It does **not** commit or tag — that's still your call:

```bash
git diff                                       # review
git commit -am "chore: release 0.2.0"
git tag -a v0.2.0 -m "v0.2.0"
git push origin main v0.2.0
```

## What happens on `git push` of a SemVer tag

1. **`ci.yml`** triggers (tag-filter `v[0-9]+.[0-9]+.[0-9]+*`), builds the container image, and emits these tags via `docker/metadata-action`:
   - `v0.2.0` → `0.2.0`, `0.2`, `0`, `latest`, `<short-sha>`
   - `v0.2.0-rc.1` → `0.2.0-rc.1`, `<short-sha>` (no rolling tags for pre-release)
2. **`release.yml`** triggers in parallel and:
   - Re-verifies `VERSION` / `pyproject.toml` / `Chart.yaml` agree with the tag.
   - Helm-packages the chart at the pinned version.
   - Pushes the chart to `oci://ghcr.io/<owner>/charts/claude-mate-agent:<version>`.
   - Generates release notes from `git log <prev-tag>..<this-tag>`.
   - Creates a GitHub Release (marked `prerelease: true` if the tag contains `-`).

## GitLab CI parity

GitLab CI emits the same tag set from `build:image` when `CI_COMMIT_TAG` matches `v[0-9]+.[0-9]+.[0-9]+*`:

- Stable: `0.2.0`, `0.2`, `0`, `latest`
- Pre-release: `0.2.0-rc.1` only

The `version:check` job in the `validate` stage enforces the same drift gate as GitHub Actions.

## Verifying locally

```bash
make version           # prints 0.1.0
make version-check     # exits 0 if all artefacts agree, non-zero otherwise
```

## Deprecation policy

A field, flag, or behaviour that will be removed in a MAJOR release must first ship in a MINOR release with:

1. A `deprecated:` note in `docs/` and the relevant Helm values/CLI help.
2. A `WARN` log line emitted at runtime when the deprecated path is taken.
3. A removal target version in the documentation (e.g. *"Removed in v2.0.0"*).

The MAJOR release commit that removes the path must update `requirement.md` to reflect the new contract.

## Why a single VERSION file

Without a single source, every artefact drifts independently — chart `appVersion` lags container tag lags pip metadata. With one file:

- One place to edit.
- One place CI gates against.
- One place release tooling consults.
- One number engineers can quote when filing bugs.

See [`requirement.md` §27](../requirement.md) for the full SemVer requirements catalogue.
