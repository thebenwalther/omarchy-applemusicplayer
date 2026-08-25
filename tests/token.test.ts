import { describe, expect, test } from "bun:test";
import { generateDeveloperToken, validateCredentials } from "../src/token";

function toPem(bytes: ArrayBuffer): string {
  const base64 = Buffer.from(bytes).toString("base64").match(/.{1,64}/g)?.join("\n");
  return `-----BEGIN PRIVATE KEY-----\n${base64}\n-----END PRIVATE KEY-----`;
}

function decodeJson(segment: string) {
  return JSON.parse(Buffer.from(segment, "base64url").toString("utf8"));
}

describe("developer token", () => {
  test("creates a short-lived origin-bound ES256 JWT", async () => {
    const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
    const privateKey = toPem(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
    const token = await generateDeveloperToken({ teamId: "ABCDEFGHIJ", keyId: "1234567890", privateKey }, "http://127.0.0.1:17689", 1000, 3600);
    const [header, payload, signature] = token.split(".");
    expect(decodeJson(header)).toEqual({ alg: "ES256", kid: "1234567890", typ: "JWT" });
    expect(decodeJson(payload)).toMatchObject({ iss: "ABCDEFGHIJ", iat: 1000, exp: 4600, origin: "http://127.0.0.1:17689" });
    expect(Buffer.from(signature, "base64url")).toHaveLength(64);
  });

  test("rejects malformed key metadata", () => {
    expect(() => validateCredentials({ teamId: "short", keyId: "123", privateKey: "nope" })).toThrow();
  });
});
