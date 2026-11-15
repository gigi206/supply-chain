Thanks for confirming the diagnosis.

The fix is ready on my side, with unit tests. On `main` at b2e65e2fa88f, the reproduction above panics without the change and passes with it, the package tests pass with `-race`, and golangci-lint reports no issue on the modified package.

Before opening the PR, I would like a maintainer's go-ahead: the issue is still labeled `triage:critical-review`, and the [AI Usage Policy](https://github.com/kyverno/community/blob/main/AI_USAGE_POLICY.md) asks that PRs with AI-generated code target accepted issues. Could a maintainer confirm that a PR is welcome now?

For context: #18533 touches the same files and addresses another case (an inline `trustedRoot` on the fast path). On its head (04385c77), the reproduction still panics; with the fix applied on top (three-way merge, no conflict), it passes, and the tests of both pass together.
