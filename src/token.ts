export interface MusicKitCredentials {
  teamId: string;
  keyId: string;
  mediaId?: string;
  privateKey: string;
}

const encoder = new TextEncoder();

function base64Url(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? encoder.encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function pemBytes(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  if (!body) throw new Error("The MusicKit .p8 private key is empty or invalid.");
  return Uint8Array.from(atob(body), character => character.charCodeAt(0));
}

export function validateCredentials(value: unknown): MusicKitCredentials {
  if (!value || typeof value !== "object") throw new Error("Missing MusicKit credentials.");
  const input = value as Record<string, unknown>;
  const teamId = String(input.teamId || "").trim();
  const keyId = String(input.keyId || "").trim();
  const mediaId = String(input.mediaId || "").trim();
  const privateKey = String(input.privateKey || "").trim();

  if (!/^[A-Z0-9]{10}$/.test(teamId)) throw new Error("Team ID must be 10 uppercase letters or digits.");
  if (!/^[A-Z0-9]{10}$/.test(keyId)) throw new Error("Key ID must be 10 uppercase letters or digits.");
  if (!privateKey.includes("BEGIN PRIVATE KEY") || !privateKey.includes("END PRIVATE KEY")) {
    throw new Error("Paste the complete contents of the MusicKit .p8 private key.");
  }

  return { teamId, keyId, mediaId, privateKey };
}

export async function generateDeveloperToken(
  credentials: MusicKitCredentials,
  origin: string,
  nowSeconds = Math.floor(Date.now() / 1000),
  ttlSeconds = 12 * 60 * 60,
): Promise<string> {
  const header = base64Url(JSON.stringify({ alg: "ES256", kid: credentials.keyId, typ: "JWT" }));
  const payload = base64Url(JSON.stringify({
    iss: credentials.teamId,
    iat: nowSeconds,
    exp: nowSeconds + Math.min(ttlSeconds, 15_552_000),
    origin,
  }));
  const signingInput = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemBytes(credentials.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(signingInput),
  ));
  return `${signingInput}.${base64Url(signature)}`;
}
