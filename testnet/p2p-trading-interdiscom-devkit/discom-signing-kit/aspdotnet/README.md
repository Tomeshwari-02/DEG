# DISCOM Signing Kit — ASP.NET / C#

C# SDK for signing Beckn protocol payloads for the DEG Ledger Service using Ed25519 + BLAKE2-512.

**In:** JSON payload (string or byte[]) + your signing config
**Out:** `Authorization` header string ready to attach to your HTTP request

## Prerequisites

- .NET 8.0 SDK
- NuGet package: `BouncyCastle.Cryptography` (v2.5.1)

## Installation

Add the `BecknSigner` project reference to your solution, or copy the two source files (`PayloadSigner.cs`, `PayloadVerifier.cs`) into your project.

```bash
# If using as a project reference
dotnet add reference path/to/BecknSigner/BecknSigner.csproj

# The BecknSigner project already includes the BouncyCastle dependency.
# If copying files manually, add:
dotnet add package BouncyCastle.Cryptography --version 2.5.1
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

Map them to `SignerConfig`:

| YAML field | Config property | Type | Required |
|---|---|---|---|
| `networkParticipant` | `SubscriberId` | `string` | Yes |
| `keyId` | `UniqueKeyId` | `string` | Yes |
| `signingPrivateKey` | `SigningPrivateKey` | `string` (base64, 32-byte Ed25519 seed) | Yes |
| — | `ExpiryDuration` | `TimeSpan` | No (default: 5 min) |

## API Reference

### `PayloadSigner(SignerConfig config)`

Constructor. Validates config and decodes the private key.

**Input:** `SignerConfig` record
**Throws:** `ArgumentException` if config is invalid (empty fields, bad base64, wrong key size)

### `string SignPayload(byte[] body)` / `string SignPayload(string body)`

Signs a JSON payload and returns the Authorization header value. The `string` overload UTF-8 encodes the body before signing.

**Input:** Raw JSON body — the exact bytes/string you will POST
**Output:** The full `Authorization` header value, e.g.:

```
Signature keyId="p2p-trading-sandbox1.com|76EU8aUq...|ed25519",algorithm="ed25519",created="1728036300",expires="1728036600",headers="(created) (expires) digest",signature="base64..."
```

### `SignedResult SignPayloadDetailed(byte[] body)`

Same as `SignPayload` but returns a record with all signing details:

```csharp
public record SignedResult
{
    public required string AuthorizationHeader { get; init; }
    public required long CreatedAt { get; init; }   // Unix timestamp
    public required long ExpiresAt { get; init; }   // Unix timestamp
    public required string Signature { get; init; }  // Raw base64 Ed25519 signature
}
```

### `PayloadVerifier.Verify(byte[] body, string authHeader, string publicKeyBase64)`

Static method. Verifies an incoming signed request.

**Inputs:**
- `body` — raw JSON payload bytes from the incoming request
- `authHeader` — the `Authorization` header value from the incoming request
- `publicKeyBase64` — the sender's Ed25519 public key (base64), looked up from the Beckn DeDi registry

**Throws:** `SignatureVerificationException` if verification fails (expired, tampered, wrong key, malformed header). Returns void on success.

### `PayloadVerifier.ParseKeyId(string keyId)`

Utility to extract the three parts from a `keyId` field (`"subscriber|keyId|algorithm"` format).

**Output:** Named tuple `(string SubscriberId, string UniqueKeyId, string Algorithm)`

## Usage

### Sign and send to Ledger Service

```csharp
using BecknSigner;

// 1. Create signer (once, at startup — e.g. register as singleton in DI)
var signer = new PayloadSigner(new SignerConfig
{
    SubscriberId = "p2p-trading-sandbox1.com",
    UniqueKeyId = "76EU8aUqHouww7gawT6EibH4bseMCumyDv3sgyXSKENGk8NDcdVwmQ",
    SigningPrivateKey = "Pc6dkYo5LeP0LkwvZXVRV9pcbeh8jDdtdHWymID5cjw=",
});

// 2. Sign any beckn payload (confirm, on_confirm, on_status, etc.)
string payload = @"{""context"":{""action"":""confirm"",...},""message"":{...}}";
string authHeader = signer.SignPayload(payload);

// 3. Attach to HTTP request
using var client = new HttpClient();
var request = new HttpRequestMessage(HttpMethod.Post, "https://ledger.example.com/record");
request.Content = new StringContent(payload, Encoding.UTF8, "application/json");
request.Headers.Add("Authorization", authHeader);

// 4. Send
var response = await client.SendAsync(request);
```

### Verify an incoming signed request

```csharp
using BecknSigner;

// In your ASP.NET controller / middleware:
[HttpPost("receive")]
public IActionResult ReceiveBecknMessage()
{
    // Read the raw body
    using var reader = new StreamReader(Request.Body);
    byte[] body = Request.Body.ReadAsBytes(); // or however you read body bytes

    string authHeader = Request.Headers["Authorization"]!;

    // Look up sender's public key from the Beckn DeDi registry
    string senderPublicKey = "KVYEWkQB2WwnttVMWfy7KrnqiD51ZDvi8vfCac2IwRE=";

    try
    {
        PayloadVerifier.Verify(body, authHeader, senderPublicKey);
        // Signature valid — proceed
        return Ok();
    }
    catch (SignatureVerificationException ex)
    {
        // Signature invalid — reject
        return Unauthorized(ex.Message);
    }
}
```

### ASP.NET Dependency Injection

```csharp
// In Program.cs or Startup.cs
builder.Services.AddSingleton(new PayloadSigner(new SignerConfig
{
    SubscriberId = builder.Configuration["Beckn:SubscriberId"]!,
    UniqueKeyId = builder.Configuration["Beckn:UniqueKeyId"]!,
    SigningPrivateKey = builder.Configuration["Beckn:SigningPrivateKey"]!,
}));

// In your controller
public class LedgerController(PayloadSigner signer) : ControllerBase
{
    [HttpPost("send")]
    public async Task<IActionResult> Send([FromBody] JsonElement payload)
    {
        string json = payload.GetRawText();
        string authHeader = signer.SignPayload(json);
        // ... attach to outgoing request
    }
}
```

## Running Tests

```bash
cd aspdotnet
dotnet test
```

Or with verbose output:

```bash
dotnet test --verbosity normal
```

Expected output:

```
  Passed PayloadSignerTests.SignAndVerify_RoundTrip_Succeeds
  Passed PayloadSignerTests.SignPayload_StringOverload_ProducesSameResult
  Passed PayloadSignerTests.SignPayloadDetailed_Returns300SecondWindow
  Passed PayloadSignerTests.Verify_RejectsTamperedPayload
  Passed PayloadSignerTests.Verify_RejectsExpiredSignature
  Passed PayloadSignerTests.Verify_RejectsWrongPublicKey
  Passed PayloadSignerTests.Constructor_ValidatesConfig
  Passed PayloadSignerTests.ParseKeyId_WorksCorrectly
  Passed UsageExampleTests.Example_SignPayloadForLedgerService
  Passed UsageExampleTests.Example_VerifyIncomingRequest

Passed!  - Failed: 0, Passed: 10, Skipped: 0
```

The test suite covers:
- **Round-trip:** sign then verify succeeds
- **String overload:** `SignPayload(string)` produces verifiable signatures
- **Detailed output:** verifies 5-minute expiry window
- **Tamper detection:** modified payload fails verification
- **Expiry enforcement:** old signatures are rejected
- **Wrong key rejection:** signature from a different key pair fails
- **Config validation:** empty fields and wrong key size
- **KeyID parsing:** valid and invalid formats
- **Usage examples:** end-to-end sign + verify workflows as runnable tests

## Project Structure

```
aspdotnet/
  BecknSigner.sln                  # Solution file
  BecknSigner/                     # Library
    BecknSigner.csproj             # .NET 8.0, depends on BouncyCastle
    PayloadSigner.cs               # SignerConfig, SignedResult, PayloadSigner
    PayloadVerifier.cs             # PayloadVerifier, SignatureVerificationException
  BecknSigner.Tests/               # Tests (xunit)
    BecknSigner.Tests.csproj
    PayloadSignerTests.cs          # Unit tests
    UsageExampleTests.cs           # End-to-end usage examples as tests
```

## Dependencies

| Package | Version | Purpose |
|---|---|---|
| `BouncyCastle.Cryptography` | 2.5.1 | Ed25519 signing/verification + BLAKE2b-512 hashing |
| `xunit` | 2.9.0 | Test framework (tests only) |
| `Microsoft.NET.Test.Sdk` | 17.8.0 | Test runner (tests only) |

## Error Handling

| Scenario | Exception | Message contains |
|---|---|---|
| Empty `SubscriberId` | `ArgumentException` | `SubscriberId` |
| Empty `UniqueKeyId` | `ArgumentException` | `UniqueKeyId` |
| Empty `SigningPrivateKey` | `ArgumentException` | `SigningPrivateKey` |
| Bad base64 in private key | `FormatException` | invalid base64 |
| Wrong key size (not 32 bytes) | `ArgumentException` | `must be 32 bytes` |
| Tampered payload | `SignatureVerificationException` | `verification failed` |
| Expired signature | `SignatureVerificationException` | `expired` |
| Malformed auth header | `SignatureVerificationException` | `Missing` |

## Signing Algorithm

1. BLAKE2b-512 hash the raw JSON body, base64-encode the digest
2. Build a canonical signing string:
   ```
   (created): {unix_timestamp}
   (expires): {unix_timestamp}
   digest: BLAKE-512={base64_hash}
   ```
3. Ed25519 sign the UTF-8 bytes of the signing string
4. Format the `Authorization` header with keyId, timestamps, and base64 signature
