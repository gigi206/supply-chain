### Kyverno CLI Version

1.18.0

### Description

1.18.0 is selected only because the version list stops there. This was observed with Kyverno 1.19.2, not tested on 1.18; the offline fast path involved (`skipSigstoreInfra`, #16298) is not in v1.18.0's `opts.go`, so 1.18 is probably not affected.

Observed with Kyverno 1.19.2, with the CLI; at admission, the request is denied. The same code is on `main` (2be1bc3fe3b4, reproduced by a unit test, below) and in v1.20.0-rc.1 (same files and dependencies, read only).

A key or certificate attestor configured with `ctlog.tsaCertChain` and `ctlog.insecureIgnoreTlog: true` cannot verify a Sigstore bundle (v0.3) that carries an RFC 3161 timestamp: evaluation panics with a nil pointer dereference. The panic happens before the timestamp is checked, so a genuine timestamp and a forged one end the same way.

```
evaluation returned an internal error, not a resource refusal error="internal error: runtime error: invalid memory address or nil pointer dereference"
```

At admission, with `validationActions: [Deny]`, a rule error denies the request ([handler.go](https://github.com/kyverno/kyverno/blob/2be1bc3fe3b4150501caac2c95ee58039824cdce/pkg/webhooks/resource/ivpol/handler.go)). So nothing is admitted that should not be, but signed timestamps cannot be used with these attestors.

Root cause (at `main` 2be1bc3fe3b4):

1. `checkOptions` takes the offline fast path for key and certificate attestors when the transparency log is ignored ([`skipSigstoreInfra`, opts.go#L93](https://github.com/kyverno/kyverno/blob/2be1bc3fe3b4150501caac2c95ee58039824cdce/pkg/image/verifiers/ivpol/cosign/opts.go#L93), added by #16298 for air-gapped key-based verification), so `CheckOpts.TrustedMaterial` stays nil. This is intended, see `TestCheckOptions_KeyBased_AirGapped`.
2. The chain from `ctlog.tsaCertChain` goes into the legacy `TSACertificate`/`TSAIntermediateCertificates`/`TSARootCertificates` fields and `UseSignedTimestamps` is set ([opts.go#L180](https://github.com/kyverno/kyverno/blob/2be1bc3fe3b4150501caac2c95ee58039824cdce/pkg/image/verifiers/ivpol/cosign/opts.go#L180)). It is merged into a trusted material only when one already exists ([opts.go#L181](https://github.com/kyverno/kyverno/blob/2be1bc3fe3b4150501caac2c95ee58039824cdce/pkg/image/verifiers/ivpol/cosign/opts.go#L181), added by #16800).
3. A detected bundle ([verifier.go#L138](https://github.com/kyverno/kyverno/blob/2be1bc3fe3b4150501caac2c95ee58039824cdce/pkg/image/verifiers/ivpol/cosign/verifier.go#L138)) is verified by `cosign.VerifyNewBundle`, which reads timestamp authorities from `TrustedMaterial` only: cosign documents `TrustedMaterial` as "exclusive with … the TSA* cert fields" ([cosign v3.1.3 verify.go#L103](https://github.com/sigstore/cosign/blob/v3.1.3/pkg/cosign/verify.go#L103)). It wraps the nil `TrustedMaterial` ([#L247](https://github.com/sigstore/cosign/blob/v3.1.3/pkg/cosign/verify.go#L247)) and requires signed timestamps ([#L279](https://github.com/sigstore/cosign/blob/v3.1.3/pkg/cosign/verify.go#L279)).
4. sigstore-go calls `TimestampingAuthorities()` on that nil interface for each timestamp in the bundle ([sigstore-go v1.3.0 tsa.go#L93](https://github.com/sigstore/sigstore-go/blob/v1.3.0/pkg/verify/tsa.go#L93), unchanged in v1.4.0).

`shouldUseSignedTimestamps` ([verifier.go#L332](https://github.com/kyverno/kyverno/blob/2be1bc3fe3b4150501caac2c95ee58039824cdce/pkg/image/verifiers/ivpol/cosign/verifier.go#L332)) already guards the automatic path against this nil `TrustedMaterial`; the explicit `tsaCertChain` path has no such guard. The docs mark `insecureIgnoreTlog` as "for testing only", but #16298 added this fast path on purpose for air-gapped key-based verification, which is the setup where a private TSA matters most.

For comparison, the cosign CLI refuses this combination cleanly: with a Sigstore bundle, `--timestamp-certificate-chain` "may only be provided using --trusted-root" (cosign v3.1.2, `cmd/cosign/cli/verify/common.go`).

Related, not duplicates:
- #17562 / #17648 (closed): same fast path, about an inline `trustedRoot` being ignored, with an error instead of a panic. From its description, #17648 would not fix this case: without `trustedRoot` the material stays nil.
- #16048 / #16054 / #16800: TSA chain on the keyless path (the keyless merge landed in #16800).
- #17109: attestations without a transparency log, a different defect.

I have a fix with unit tests, verified on `main` and on v1.19.2, and can open a PR once this issue is triaged.

The analysis and the reproduction were done with an AI assistant (Claude) in my test environment; I reviewed the results.

### Steps to reproduce

Self-contained reproduction, as a test in `pkg/image/verifiers/ivpol/cosign` (uses sigstore-go's virtual TSA and the package's in-memory registry helpers, no external registry or TSA). On `main` 2be1bc3fe3b4 it panics in `TimestampingAuthorities()`:

<details>
<summary>repro_tsa_test.go</summary>

```go
package cosign

import (
	"context"
	"encoding/pem"
	"fmt"
	"strings"
	"testing"

	"github.com/go-logr/logr"
	"github.com/kyverno/api/api/policies.kyverno.io/v1beta1"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	protocommon "github.com/sigstore/protobuf-specs/gen/pb-go/common/v1"
	"github.com/sigstore/sigstore-go/pkg/root"
	"github.com/sigstore/sigstore-go/pkg/sign"
	"github.com/sigstore/sigstore-go/pkg/testing/ca"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/encoding/protojson"
)

// A key-signed Sigstore bundle carrying a genuine RFC 3161 timestamp, verified by a
// key attestor with ctlog.tsaCertChain and insecureIgnoreTlog: panics on main.
func TestRepro_KeyAttestor_TSACertChain_TimestampedBundle(t *testing.T) {
	tsa, err := ca.NewVirtualSigstore()
	require.NoError(t, err)
	repo, _ := newBundleRegistry(t)
	subject := pushSubject(t, repo, "subject")
	img := fetchTestImage(t, repo.Tag("subject").String())

	kp, err := sign.NewEphemeralKeypair(nil)
	require.NoError(t, err)
	statement := fmt.Sprintf(`{"_type":"https://in-toto.io/Statement/v1","predicateType":"https://example.com/predicate","subject":[{"name":"subject","digest":{"sha256":%q}}],"predicate":{}}`, subject.Digest.Hex)
	pb, err := sign.Bundle(&sign.DSSEData{Data: []byte(statement), PayloadType: "application/vnd.in-toto+json"}, kp, sign.BundleOptions{})
	require.NoError(t, err)
	tsr, err := tsa.TimestampResponse(pb.GetDsseEnvelope().GetSignatures()[0].GetSig())
	require.NoError(t, err)
	pb.VerificationMaterial.TimestampVerificationData = &protobundle.TimestampVerificationData{
		Rfc3161Timestamps: []*protocommon.RFC3161SignedTimestamp{{SignedTimestamp: tsr}},
	}
	raw, err := protojson.Marshal(pb)
	require.NoError(t, err)
	pushReferrer(t, repo, subject, raw, testBundleMediaType, testBundleMediaType)
	pubPEM, err := kp.GetPublicKeyPem()
	require.NoError(t, err)

	authority := tsa.TimestampingAuthorities()[0].(*root.SigstoreTimestampingAuthority)
	var chain strings.Builder
	for _, c := range append(append(authority.Intermediates[:0:0], authority.Leaf), append(authority.Intermediates, authority.Root)...) {
		require.NoError(t, pem.Encode(&chain, &pem.Block{Type: "CERTIFICATE", Bytes: c.Raw}))
	}
	attestor := &v1beta1.Attestor{Name: "signer", Cosign: &v1beta1.Cosign{
		Key:   &v1beta1.Key{Data: pubPEM},
		CTLog: &v1beta1.CTLog{InsecureIgnoreTlog: true, TSACertChain: chain.String()},
	}}

	require.NoError(t, NewVerifier(nil, logr.Discard()).VerifyImageSignature(context.TODO(), img, attestor))
}
```

</details>

```
go test -run TestRepro_KeyAttestor_TSACertChain_TimestampedBundle ./pkg/image/verifiers/ivpol/cosign/
--- FAIL: TestRepro_KeyAttestor_TSACertChain_TimestampedBundle
panic: runtime error: invalid memory address or nil pointer dereference [recovered, repanicked]
```

With real artifacts: our bundles come from an internal job that re-emits the attestation as a Sigstore bundle (v0.3) with an RFC 3161 timestamp from a private TSA (key-signed, no transparency log), stored in a separate repository (`source.repository`). This policy, applied with `kyverno apply` 1.19.2 to a pod using the image, reproduces it:

```yaml
apiVersion: policies.kyverno.io/v1
kind: ImageValidatingPolicy
metadata:
  name: provenance-timestamped
spec:
  validationActions: [Deny]
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE"]
        resources: ["pods"]
  matchImageReferences:
    - glob: "registry.example.com/*"
  attestors:
    - name: signer
      cosign:
        key:
          data: |
            -----BEGIN PUBLIC KEY-----
            ...
            -----END PUBLIC KEY-----
        source:
          repository: registry.example.com/timestamps/bundles
        ctlog:
          insecureIgnoreTlog: true
          tsaCertChain: |
            -----BEGIN CERTIFICATE-----
            ... TSA leaf, intermediates, root ...
            -----END CERTIFICATE-----
  attestations:
    - name: prov
      intoto:
        type: https://slsa.dev/provenance/v1
  validations:
    - expression: >-
        images.containers.map(i, verifyAttestationSignatures(i, attestations.prov, [attestors.signer])).all(e, e > 0)
      message: "provenance without a valid RFC 3161 timestamp"
```

| Bundle | Kyverno 1.19.2 |
|---|---|
| valid, policy without `tsaCertChain` | pass |
| valid, with `tsaCertChain` | error (nil pointer) |
| timestamp tampered (one byte) | error (nil pointer) |
| valid timestamp of another signature | error (nil pointer) |
| timestamp from a foreign TSA | error (nil pointer) |
| no timestamp | fail (`threshold not met for verified signed timestamps: 0 < 1`) |

cosign v3.1.4 (`verify-attestation --insecure-ignore-tlog --use-signed-timestamps --trusted-root`, with a trusted root for the TSA made by `cosign trusted-root create --tsa=...`) accepts the valid bundle and refuses the other four.

### Expected behavior

Verify the timestamp against the configured TSA, as cosign does: accept a genuine timestamp; refuse a tampered timestamp, a timestamp over another signature or one from another TSA, with a clear reason. In no case panic.


### Screenshots

_No response_

### Kyverno logs

```Shell
Stack trace of the reproduction test on `main` 2be1bc3fe3b4:


panic: runtime error: invalid memory address or nil pointer dereference
github.com/sigstore/cosign/v3/pkg/cosign.(*verifyTrustedMaterial).TimestampingAuthorities
github.com/sigstore/sigstore-go/pkg/verify.verifySignedTimestamp                 sigstore-go@v1.3.0/pkg/verify/tsa.go:93
github.com/sigstore/sigstore-go/pkg/verify.VerifySignedTimestamp                 sigstore-go@v1.3.0/pkg/verify/tsa.go:47
github.com/sigstore/sigstore-go/pkg/verify.VerifySignedTimestampWithThreshold    sigstore-go@v1.3.0/pkg/verify/tsa.go:82
github.com/sigstore/sigstore-go/pkg/verify.(*Verifier).VerifyObserverTimestamps  sigstore-go@v1.3.0/pkg/verify/signed_entity.go:879
github.com/sigstore/sigstore-go/pkg/verify.(*Verifier).Verify                    sigstore-go@v1.3.0/pkg/verify/signed_entity.go:637
github.com/sigstore/cosign/v3/pkg/cosign.VerifyNewBundle                         cosign/v3@v3.1.3/pkg/cosign/verify_bundle.go:42
github.com/kyverno/kyverno/pkg/image/verifiers/ivpol/cosign.verifyBundles        pkg/image/verifiers/ivpol/cosign/verifier.go:275
github.com/kyverno/kyverno/pkg/image/verifiers/ivpol/cosign.(*Verifier).VerifyImageSignature  pkg/image/verifiers/ivpol/cosign/verifier.go:364


Kyverno CLI 1.19.2, verbose output (`-v 6`):


evaluation returned an internal error, not a resource refusal error="internal error: runtime error: invalid memory address or nil pointer dereference"
```

### Slack discussion

_No response_

### Troubleshooting

- [x] I have read and followed the [troubleshooting guide](https://kyverno.io/docs/troubleshooting/).
- [x] I have searched other issues in this repository and mine is not recorded.
