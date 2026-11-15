## Explanation

A key or certificate attestor configured with `ctlog.tsaCertChain` and `ctlog.insecureIgnoreTlog: true` cannot verify a Sigstore bundle that carries an RFC 3161 timestamp: the evaluation panics with a nil pointer dereference before the timestamp is checked, so a genuine timestamp is never accepted (at admission, the rule error denies the request). This PR fixes that behaviour: such bundles are now verified against the configured TSA chain. For key attestors, tampered and foreign timestamps are refused (certificate attestors are tested with genuine timestamps).

## Related issue

Fixes #18525

## Milestone of this PR

## Documentation (required for features)

Not applicable: this is a bug fix, with no new or changed configuration.

## What type of PR is this

/kind bug

## Proposed Changes

- `verifier.go`: when a Sigstore bundle is verified with signed timestamps and `CheckOpts.TrustedMaterial` is nil (the `skipSigstoreInfra` path), build a trusted material holding only the TSA from `ctlog.tsaCertChain`, one entry per root of the chain, as the cosign CLI requires with `--trusted-root`. v2 signatures keep using the legacy `TSA*` fields. A chain without its root CA returns an explicit error instead of panicking.
- `opts.go`: the existing wrapping of the trusted material with the TSA chain moves to a shared helper, `tsaTrustedMaterials`, without behaviour change.
- `tsa_cert_chain_test.go`: key attestors with genuine, tampered, foreign-TSA and missing timestamps, for v2 signatures and Sigstore bundles; certificate attestors with genuine timestamps on Sigstore bundles; a chain without its root; the trusted material built for each path.

Two cases keep their current behaviour, and their tests pass both before and after the change: with `tsaCertChain` set, a bundle without a timestamp is refused (`threshold not met for verified signed timestamps`); without `tsaCertChain`, a timestamped bundle still verifies, since no timestamp is required.

Verified locally with go1.27.3 on `main` (b2e65e2fa88f): the package tests pass with `-race -covermode atomic`, golangci-lint v2.14.0 with `.golangci.yml` reports no issue on the modified package, and the reproduction from #18525 panics without the change and passes with it.

### Proof Manifests

No policy manifest is attached: reproducing the bug needs a registry holding a Sigstore bundle with an RFC 3161 timestamp, and a policy whose `ctlog.tsaCertChain` matches that TSA. The tests build both in-process (sigstore-go's virtual TSA and the package's in-memory registry), and the self-contained reproduction is in #18525 ("Steps to reproduce").

## Checklist

- [x] I have read the [contributing guidelines](https://github.com/kyverno/kyverno/blob/main/CONTRIBUTING.md).
- [x] I have read the [AI Usage Policy](https://github.com/kyverno/community/blob/main/AI_USAGE_POLICY.md). If I used AI assistance, I have disclosed it in my commit(s) (e.g., via `Co-authored-by` or `Assisted-by` trailer).
- [ ] I have read the [PR documentation guide](https://github.com/kyverno/kyverno/blob/main/.github/pr_documentation.md) and followed the process including adding proof manifests to this PR.
- [x] This is a bug fix and I have added unit tests that prove my fix is effective.
- [ ] This is a feature and I have added CLI tests that are applicable.
- [ ] My PR needs to be cherry picked to a specific release branch which is <replace>.
- [ ] My PR contains new or altered behavior to Kyverno and
  - [ ] CLI support should be added and my PR doesn't contain that functionality.

## Further Comments

Relation with #18533 (open, same files): it resolves an inline `trustedRoot` on the fast path, but without one `TrustedMaterial` stays nil, so this case still panics there. Measured locally on its head (04385c77): the reproduction from #18525 panics; with this change applied on top (three-way merge, no conflict), it passes, and the tests of both PRs pass together.

The fix and the tests were written with an AI assistant (Claude), disclosed in the commit with `Assisted-by`.
