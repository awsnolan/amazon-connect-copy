# End-to-End Test Automation

Automated test suite for the Amazon Connect DR Toolkit.

## Quick Start

```bash
# Run offline tests (no AWS credentials needed)
./tests/run_tests.sh

# Run with verbose output
./tests/run_tests.sh --verbose

# Run offline + live integration tests (requires AWS credentials)
./tests/run_tests.sh --live
```

## Test Suites

| Suite | Tests | Requires AWS | What it validates |
|-------|-------|--------------|-------------------|
| 1. Script Syntax | ~56 | No | `bash -n` on all scripts and lib modules |
| 2. CLI Interface | 8 | No | Version flags, usage text, exit codes |
| 3. Local Validation | 5 | No | `connect_validate -m local` with fixtures |
| 4. Plan (offline) | 8 | No | `connect_plan` produces correct helper files |
| 5. Restore Dry-Run | 2 | No | `connect_restore -d` runs without AWS |
| 6. JSON Structure | 8 | No | Fixture files have required fields |
| 7. Cross-Account Remapping | 2 | No | Plan detects different accounts, generates mappings |
| 8. Output Formatting | 2 | No | `--no-color` and `NO_COLOR` suppress ANSI codes |
| 9. Plan Correctness | 7 | No | New/old resource classification matches expectations |
| 10. SED Remapping | 8 | No | ID substitutions remap flow content correctly |
| 11. Identical Source=Target | 3 | No | Same-instance plan produces no changes |
| 12. Validate JSON Output | 6 | No | JSON mode schema (layers, tests, result, counts) |
| 13. Restore Dry-Run Detail | 3 | No | Dry-run mentions resources, doesn't mutate files |
| 14. Edge Cases | 4 | No | Empty manifests, --only single layer, minimal plan |
| 15. Live Integration | 6 | Yes | Full backup → plan → restore → validate pipeline |

## Live Integration Tests

Suite 9 runs the full pipeline against real Connect instances. Set these
environment variables before running with `--live`:

```bash
export CONNECT_SOURCE_INSTANCE=<instance-alias>
export CONNECT_TARGET_INSTANCE=<target-instance-id>
export CONNECT_SOURCE_PROFILE=<aws-profile>       # optional
export CONNECT_TARGET_PROFILE=<aws-profile>       # optional

./tests/run_tests.sh --live --verbose
```

## Fixtures

`tests/fixtures/` contains two synthetic instance directories with placeholder
IDs (111111111111 / 222222222222) that exercise the full plan and local
validation logic without any real AWS resources.

- `fixtures/source/` — 3 flows, 2 queues, 2 routing profiles, 3 security
  profiles, 3 users, 2 hours, 2 Lambda deps, 1 Lex bot
- `fixtures/target/` — subset of source (1 queue, 1 routing profile, 2 flows)
  simulating a warm-standby DR instance

## Adding Tests

Tests are plain bash functions using the `test_start` / `test_pass` / `test_fail`
helpers. Add new tests to the relevant suite section in `run_tests.sh`.

## CI/CD Integration

For automated pipelines, use the JSON exit code:
```bash
./tests/run_tests.sh || exit 1
```

Combine with the live tests in CodeBuild:
```yaml
phases:
  build:
    commands:
      - ./tests/run_tests.sh --live
```
