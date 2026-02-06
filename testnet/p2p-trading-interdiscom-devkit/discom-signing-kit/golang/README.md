# DISCOM Signing Kit — Go

Go SDK for signing Beckn protocol payloads for the DEG Ledger Service using Ed25519 + BLAKE2-512.

**In:** JSON payload bytes (any Beckn action) + your signing config
**Out:** `Authorization` header string ready to attach to your HTTP request

## Prerequisites

- Go 1.21+
- No CGO required — pure Go

## Installation

```bash
go get github.com/beckn/deg-discom-signing-kit
```

## Configuration

You need three values from your beckn-onix YAML config (the `degledgerrecorder` or `simplekeymanager` section):

```yaml
# From your local-p2p-bap.yaml or similar
degledgerrecorder:
  signingPrivateKey: Pc6dkYo5LeP0LkwvZXVRV9pcbeh8jDdtdHWymID5cjw=
  networkParticipant: p2p-trading-sandbox1.com
  keyId: 76EU8aUqHouww7gawT6EibH4bseMCumyDv3sgyXSKENGk8NDcdVwmQ
```

Map them to `signer.Config`:

| YAML field | Config field | Type | Required |
|---|---|---|---|
| `networkParticipant` | `SubscriberID` | `string` | Yes |
| `keyId` | `UniqueKeyID` | `string` | Yes |
| `signingPrivateKey` | `SigningPrivateKey` | `string` (base64, 32-byte Ed25519 seed) | Yes |
| — | `ExpiryDuration` | `time.Duration` | No (default: 5 min) |

## API Reference

### `signer.New(cfg Config) (*Signer, error)`

Creates a new signer. Validates config and decodes the private key.

**Input:** `signer.Config` struct
**Output:** `*Signer` (or error if config is invalid — missing fields, bad base64, wrong key size)

### `(*Signer) SignPayload(body []byte) (string, error)`

Signs a JSON payload and returns the Authorization header value.

**Input:** `[]byte` — raw JSON body (the exact bytes you will POST)
**Output:** `string` — the full `Authorization` header value, e.g.:

```
Signature keyId="p2p-trading-sandbox1.com|76EU8aUq...|ed25519",algorithm="ed25519",created="1728036300",expires="1728036600",headers="(created) (expires) digest",signature="base64..."
```

### `(*Signer) SignPayloadDetailed(body []byte) (*SignedResult, error)`

Same as `SignPayload` but returns a struct with all signing details:

```go
type SignedResult struct {
    AuthorizationHeader string // Full header value
    CreatedAt           int64  // Unix timestamp
    ExpiresAt           int64  // Unix timestamp
    Signature           string // Raw base64 Ed25519 signature
}
```

### `signer.Verify(body []byte, authHeader string, publicKeyBase64 string) error`

Verifies an incoming signed request. Package-level function (no signer instance needed).

**Inputs:**
- `body` — raw JSON payload bytes from the incoming request
- `authHeader` — the `Authorization` header value from the incoming request
- `publicKeyBase64` — the sender's Ed25519 public key (base64), looked up from the Beckn DeDi registry

**Output:** `nil` if valid, or an error describing what failed (expired, tampered, wrong key, malformed header)

### `signer.ParseKeyID(keyID string) (subscriberID, uniqueKeyID, algorithm string, err error)`

Utility to extract the three parts from a `keyId` field (`"subscriber|keyId|algorithm"` format).

## Usage

### Sign and send to Ledger Service

```go
import (
    "net/http"
    "strings"

    signer "github.com/beckn/deg-discom-signing-kit"
)

// 1. Create signer (once, at startup)
s, err := signer.New(signer.Config{
    SubscriberID:     "p2p-trading-sandbox1.com",
    UniqueKeyID:      "76EU8aUqHouww7gawT6EibH4bseMCumyDv3sgyXSKENGk8NDcdVwmQ",
    SigningPrivateKey: "Pc6dkYo5LeP0LkwvZXVRV9pcbeh8jDdtdHWymID5cjw=",
})
if err != nil {
    log.Fatal(err)
}

// 2. Sign any beckn payload (confirm, on_confirm, on_status, etc.)
payload := []byte(`{"context":{"action":"confirm",...},"message":{...}}`)
authHeader, err := s.SignPayload(payload)
if err != nil {
    log.Fatal(err)
}

// 3. Attach to HTTP request
req, _ := http.NewRequest("POST", "https://ledger.example.com/record",
    strings.NewReader(string(payload)))
req.Header.Set("Content-Type", "application/json")
req.Header.Set("Authorization", authHeader)

// 4. Send
resp, err := http.DefaultClient.Do(req)
```

### Verify an incoming signed request

```go
// On the receiving side, verify the sender's signature
body, _ := io.ReadAll(req.Body)
authHeader := req.Header.Get("Authorization")

// Look up sender's public key from the Beckn DeDi registry
senderPublicKey := "KVYEWkQB2WwnttVMWfy7KrnqiD51ZDvi8vfCac2IwRE="

err := signer.Verify(body, authHeader, senderPublicKey)
if err != nil {
    // Signature invalid — reject the request
    http.Error(w, "unauthorized", http.StatusUnauthorized)
    return
}
// Signature valid — proceed
```

## Running Tests

```bash
cd golang
go test -v ./...
```

Expected output:

```
=== RUN   TestSignAndVerifyRoundTrip
--- PASS: TestSignAndVerifyRoundTrip
=== RUN   TestSignPayloadDetailed
--- PASS: TestSignPayloadDetailed
=== RUN   TestVerifyRejectsTamperedPayload
--- PASS: TestVerifyRejectsTamperedPayload
=== RUN   TestVerifyRejectsExpiredSignature
--- PASS: TestVerifyRejectsExpiredSignature
=== RUN   TestVerifyRejectsWrongPublicKey
--- PASS: TestVerifyRejectsWrongPublicKey
=== RUN   TestNewValidatesConfig
--- PASS: TestNewValidatesConfig
=== RUN   TestParseKeyID
--- PASS: TestParseKeyID
=== RUN   Example_signAndSend
--- PASS: Example_signAndSend
=== RUN   Example_verify
--- PASS: Example_verify
PASS
```

The test suite covers:
- **Round-trip:** sign then verify succeeds
- **Detailed output:** verifies 5-minute expiry window
- **Tamper detection:** modified payload fails verification
- **Expiry enforcement:** old signatures are rejected
- **Wrong key rejection:** signature from a different key pair fails
- **Config validation:** missing fields, bad base64, wrong key size
- **KeyID parsing:** valid and invalid formats

## Dependencies

| Package | Version | Purpose |
|---|---|---|
| `golang.org/x/crypto` | v0.31.0 | BLAKE2b-512 hashing |
| `crypto/ed25519` (stdlib) | — | Ed25519 signing/verification |

## Signing Algorithm

1. BLAKE2-512 hash the raw JSON body, base64-encode the digest
2. Build a canonical signing string:
   ```
   (created): {unix_timestamp}
   (expires): {unix_timestamp}
   digest: BLAKE-512={base64_hash}
   ```
3. Ed25519 sign the UTF-8 bytes of the signing string
4. Format the `Authorization` header with keyId, timestamps, and base64 signature
