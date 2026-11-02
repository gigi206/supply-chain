<!-- 🎉⛓🎉 Thank you for the PR!!! 🎉⛓🎉 -->

# Changes

When no signer can be configured for a signable type (missing key material, or a KMS backend that is unreachable or sealed), `ObjectSigner.Sign()` logs `No signer %s configured for %s`. Since #1834 the object is no longer marked as signed, but this path still does not call `recordError()`, so `watcher_{taskrun,pipelinerun}_signing_failures_total` stay at 0 during a KMS outage, while payload creation, marshalling, signing, tlog and storage failures are counted.

This PR:
- records a new `error_type`, `signer_unavailable`, on that path (one line in `pkg/chains/signing.go`, one constant in `pkg/metrics/common.go`);
- adds `TestSigner_Sign_NoSignerRecordsError` (TaskRun and PipelineRun): the error type is recorded, the object is not marked as signed and a retry is recorded. The test fails without the change;
- lists the `error_type` values in `docs/metrics.md`.

Related to #1796 (the "no signer" path). The "format not found" path of #1796 is left untouched: `artifacts.*.format` is already validated when the ConfigMap is loaded, and several existing tests rely on an empty OCI artifact config being skipped there, so it seemed better discussed separately.

## Manual test

On a k3s cluster with a KMS signer (OpenBao, `hashivault://`), with v0.29.9 + #1834 + this change (the signing code is the same as on `main`). OpenBao was sealed, then a PipelineRun ran:
- the PipelineRun and its three TaskRuns ended with `chains.tekton.dev/signed=failed` and `retries=3`, within seconds of completion;
- `watcher_taskrun_signing_failures_total{error_type="signer_unavailable"}` reached 20, and the PipelineRun counter 7. That matches the 27 `No signer kms configured` log lines;
- `marked_signed_total` and `sign_created_total` stayed at 0;
- our alert on these failure counters fired.

With v0.29.9 alone, the same scenario marks the four objects `signed=true` with no signature, and every failure counter stays at 0.

One observation, not addressed here: the 3 retries are exhausted within a few seconds (the workqueue backoff starts at 5 ms, and each annotation patch probably triggers a new reconcile). So a run that completes during a KMS outage ends `signed=failed` and is not retried once the KMS is back.

As far as I can tell, #1834 is not in any release yet, nor on the `release-v0.2x.x` branches. Would a backport be possible?

This PR was developed with assistance from Claude (Claude Code). I reviewed and tested the change.

# Submitter Checklist

As the author of this PR, please check off the items in this checklist:

- [x] Has [Docs](https://github.com/tektoncd/community/blob/main/standards.md#docs) included if any changes are user facing
- [x] Has [Tests](https://github.com/tektoncd/community/blob/main/standards.md#tests) included if any functionality added or changed
- [x] Follows the [commit message standard](https://github.com/tektoncd/community/blob/main/standards.md#commits)
- [x] Meets the [Tekton contributor standards](https://github.com/tektoncd/community/blob/main/standards.md) (including
  functionality, content, code)
- [x] Release notes block below has been updated with any user facing changes (API changes, bug fixes, changes requiring upgrade notices or deprecation warnings)
- [ ] Release notes contains the string "action required" if the change requires additional action from users switching to the new release

# Release Notes

```release-note
Signing failures caused by an unavailable signer (missing key material, unreachable or sealed KMS) are now counted in watcher_taskrun_signing_failures_total and watcher_pipelinerun_signing_failures_total with error_type="signer_unavailable".
```
