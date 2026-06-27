# full_cover

Multi-package test coverage for Dart and Flutter projects.

Runs tests across all packages, merges coverage data, and generates an HTML report with line, branch, and function coverage.

![Coverage report screenshot](https://github.com/llfbandit/full_cover/blob/main/full_cover/doc/img/screen.png)

---

## Features

- **Auto-discovery** — packages are discovered from `workspace:` entries or local `path:` dependencies in the root `pubspec.yaml`
- **Dart & Flutter** — automatically detects Flutter packages via `pubspec.yaml` dependencies
- **Zero-coverage injection** — untested source files are included with 0 % coverage so the true rate is reported
- **Condition-level branches** — AST analysis replaces the VM's line-level branch data with real if/else, ternary, and switch branches
- **Function coverage** — extracted from the AST alongside branch data
- **HTML report** — partial-coverage highlighting, and per-file annotated source views

---

## Installation

```sh
dart pub global activate full_cover
```
... or as dev dependency.

## Usage

```sh
# Run from your workspace root (where full_cover.yaml lives)
full_cover

# Skip re-running tests; use existing coverage/lcov.info files
full_cover --no-test

# Remove all coverage output folders (global and per-package)
full_cover --clean
```

---

## Configuration

Create `full_cover.yaml` alongside your root `pubspec.yaml` ([Template](https://github.com/llfbandit/full_cover/blob/main/full_cover/doc/full_cover.yaml)):

| Key                           | Default    | Description                                                         |
|-------------------------------|------------|---------------------------------------------------------------------|
| `package_excludes[].package`  | —          | Package path relative to workspace root                             |
| `package_excludes[].excludes` | —          | Glob patterns to exclude within that package                        |
| `global_excludes.files`       | —          | Glob patterns applied to every package                              |
| `output.directory`            | `coverage` | Base folder for all coverage output                                 |
| `output.global`               | `true`     | Write merged `lcov.info` to `output.directory`                      |
| `output.html.global`          | `false`    | Generate merged HTML report under `output.directory/html.directory` |
| `output.html.package`         | `false`    | Generate per-package HTML report inside each package's `coverage/`  |
| `output.html.directory`       | `html`     | HTML subfolder relative to `output.directory`                       |
| `limits.line.minimum`         | `30`       | Line coverage % below which the report is red                       |
| `limits.line.average`         | `60`       | Line coverage % at or above which the report is green               |
| `limits.branch.minimum`       | `30`       | Branch coverage % below which the report is red                     |
| `limits.branch.average`       | `60`       | Branch coverage % at or above which the report is green             |
| `limits.function.minimum`     | `30`       | Function coverage % below which the report is red                   |
| `limits.function.average`     | `60`       | Function coverage % at or above which the report is green           |

---

### Package discovery

The root package is always included. Sub-packages are resolved from the root `pubspec.yaml` in order:

1. `workspace:` list (Dart workspace resolution)
2. `path:` entries in `dependencies`, `dev_dependencies`, and `dependency_overrides`

---

## Motivation

I started this project a while back for personal needs. It was also a way to learn more about the internals of the Dart VM.

Hope you'll like it!
