# GitHub Actions outage runbook

An Actions outage blocks hosted evidence; it does not justify weakening Record's
branch protection or release controls.

## During the incident

1. Confirm the incident on [GitHub Status](https://www.githubstatus.com/).
2. Keep required checks, signed commits, protected environments, and approval
   rules enabled. Do not use an administrator bypass to merge or release.
3. Work in narrow branches and push commits while Git operations are healthy.
4. Before each checkpoint, run `./scripts/ci/local-gate.sh`. Record the commit
   ID, macOS/Xcode/Swift versions printed by preflight, test count, sanitizer
   result when relevant, and any manual hardware evidence in the issue.
5. Do not place signing files, API keys, captured media, transcripts, or model
   assets in branches or CI evidence.

A self-hosted Actions runner is not a dependable outage bypass: registration,
job orchestration, webhooks, and APIs may share the affected control plane. It
also expands the trust boundary of a public repository. Record therefore uses
the local gate for progress and waits for hosted verification before merging.

## Recovery

1. Wait until Actions is operational rather than merely monitoring.
2. Rebase each narrow branch in dependency order and rerun the local gate.
3. Open or refresh PRs without changing the required-check configuration.
4. Require fresh hosted results for workflow lint, Swift/package validation,
   dependency review, and any applicable security analysis.
5. Merge with the configured squash-only, linear-history policy. Delete merged
   branches automatically.

Release tags are not created during an outage. A release resumes only from a
signed semantic-version tag whose commit has passed the restored protected
workflow and the `release` environment approval.
