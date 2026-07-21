import { env } from "../_generated/server";
import { CrmError, type CrmConfig } from "./provider";

const ENCRYPTED_API_KEY_PREFIX = "enc:v1:";

export type StoredCrmConfig = {
  provider: string;
  baseUrl?: string;
  encryptedApiKey?: string;
};

export async function storedCrmConfigFromInput(
  crm: CrmConfig,
): Promise<StoredCrmConfig> {
  const apiKey = normalizedString(crm.apiKey);
  if (apiKey === undefined) {
    throw CrmError.configuration("CRM API key is not configured");
  }
  return {
    provider: crm.provider,
    baseUrl: normalizedString(crm.baseUrl),
    encryptedApiKey: await encryptApiKey(apiKey),
  };
}

export async function materializeCrmConfig(
  stored: StoredCrmConfig,
): Promise<CrmConfig> {
  return {
    provider: stored.provider,
    baseUrl: normalizedString(stored.baseUrl),
    apiKey:
      stored.encryptedApiKey === undefined
        ? undefined
        : await decryptApiKey(stored.encryptedApiKey),
  };
}

async function encryptApiKey(apiKey: string) {
  const key = await encryptionKey();
  const iv = new Uint8Array(12);
  crypto.getRandomValues(iv);
  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    new TextEncoder().encode(apiKey),
  );
  return [
    ENCRYPTED_API_KEY_PREFIX,
    base64UrlEncode(iv),
    ".",
    base64UrlEncode(new Uint8Array(encrypted)),
  ].join("");
}

async function decryptApiKey(value: string) {
  if (!value.startsWith(ENCRYPTED_API_KEY_PREFIX)) {
    return value;
  }
  const encoded = value.slice(ENCRYPTED_API_KEY_PREFIX.length);
  const [ivText, cipherText] = encoded.split(".");
  if (ivText === undefined || cipherText === undefined) {
    throw CrmError.configuration("Stored CRM API key is malformed");
  }
  const key = await encryptionKey();
  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: base64UrlDecode(ivText) },
    key,
    base64UrlDecode(cipherText),
  );
  return new TextDecoder().decode(decrypted);
}

async function encryptionKey() {
  const secret = normalizedString(env.CRM_SECRET_ENCRYPTION_KEY);
  if (secret === undefined) {
    throw CrmError.configuration("CRM_SECRET_ENCRYPTION_KEY is not configured");
  }
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(secret),
  );
  return await crypto.subtle.importKey("raw", digest, "AES-GCM", false, [
    "encrypt",
    "decrypt",
  ]);
}

function base64UrlEncode(bytes: Uint8Array) {
  return Buffer.from(bytes)
    .toString("base64")
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function base64UrlDecode(text: string) {
  const padded = text + "=".repeat((4 - (text.length % 4)) % 4);
  return Uint8Array.from(
    Buffer.from(padded.replaceAll("-", "+").replaceAll("_", "/"), "base64"),
  );
}

function normalizedString(value: unknown) {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed === "" ? undefined : trimmed;
}
