using System.Text;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;

namespace BecknSigner;

/// <summary>
/// Verifies Beckn protocol Authorization header signatures.
/// </summary>
public static class PayloadVerifier
{
    /// <summary>
    /// Verifies that the Authorization header is a valid signature for the given body.
    /// </summary>
    /// <param name="body">The raw JSON payload bytes.</param>
    /// <param name="authHeader">The full Authorization header value.</param>
    /// <param name="publicKeyBase64">The sender's base64-encoded Ed25519 public key.</param>
    /// <exception cref="SignatureVerificationException">If verification fails.</exception>
    public static void Verify(byte[] body, string authHeader, string publicKeyBase64)
    {
        VerifyAt(body, authHeader, publicKeyBase64, DateTimeOffset.UtcNow);
    }

    /// <summary>
    /// Verifies at a specific time (useful for testing).
    /// </summary>
    public static void VerifyAt(byte[] body, string authHeader, string publicKeyBase64, DateTimeOffset now)
    {
        var (created, expires, signature) = ParseAuthHeader(authHeader);

        long currentTime = now.ToUnixTimeSeconds();
        if (created > currentTime)
            throw new SignatureVerificationException($"Signature not yet valid (created {created} > now {currentTime})");
        if (currentTime > expires)
            throw new SignatureVerificationException($"Signature expired (expires {expires} < now {currentTime})");

        byte[] signatureBytes = Convert.FromBase64String(signature);
        string signingString = PayloadSigner.BuildSigningString(body, created, expires);
        byte[] signingBytes = Encoding.UTF8.GetBytes(signingString);

        byte[] publicKeyBytes = Convert.FromBase64String(publicKeyBase64);
        var publicKey = new Ed25519PublicKeyParameters(publicKeyBytes, 0);

        var verifier = new Ed25519Signer();
        verifier.Init(false, publicKey);
        verifier.BlockUpdate(signingBytes, 0, signingBytes.Length);

        if (!verifier.VerifySignature(signatureBytes))
            throw new SignatureVerificationException("Signature verification failed");
    }

    /// <summary>
    /// Parses the keyId field from an Authorization header.
    /// Format: "subscriber_id|unique_key_id|algorithm"
    /// </summary>
    public static (string SubscriberId, string UniqueKeyId, string Algorithm) ParseKeyId(string keyId)
    {
        var parts = keyId.Split('|');
        if (parts.Length != 3)
            throw new ArgumentException($"Invalid keyId format, expected 'subscriber|keyId|algorithm', got '{keyId}'");
        return (parts[0], parts[1], parts[2]);
    }

    private static (long Created, long Expires, string Signature) ParseAuthHeader(string header)
    {
        header = header.StartsWith("Signature ", StringComparison.OrdinalIgnoreCase)
            ? header["Signature ".Length..]
            : header;

        var parameters = new Dictionary<string, string>();
        foreach (var part in header.Split(','))
        {
            var eqIndex = part.IndexOf('=');
            if (eqIndex > 0)
            {
                string key = part[..eqIndex].Trim();
                string value = part[(eqIndex + 1)..].Trim().Trim('"');
                parameters[key] = value;
            }
        }

        if (!parameters.TryGetValue("created", out var createdStr) || !long.TryParse(createdStr, out long created))
            throw new SignatureVerificationException("Missing or invalid 'created' in auth header");

        if (!parameters.TryGetValue("expires", out var expiresStr) || !long.TryParse(expiresStr, out long expires))
            throw new SignatureVerificationException("Missing or invalid 'expires' in auth header");

        if (!parameters.TryGetValue("signature", out var signature))
            throw new SignatureVerificationException("Missing 'signature' in auth header");

        return (created, expires, signature);
    }
}

public class SignatureVerificationException : Exception
{
    public SignatureVerificationException(string message) : base(message) { }
}
