"use node";

import { lookup as dnsLookup } from "node:dns/promises";
import type { IncomingHttpHeaders } from "node:http";
import { request as httpsRequest, type RequestOptions } from "node:https";
import { isIP, type LookupFunction } from "node:net";
import { CrmError } from "./provider";

type SafeFetch = (input: string | URL, init?: RequestInit) => Promise<Response>;

const MAX_REDIRECTS = 5;
let testFetch: SafeFetch | undefined;

export function setSafeCrmFetchForTesting(fetcher: SafeFetch | undefined) {
  testFetch = fetcher;
}

export async function safeCrmFetch(input: string | URL, init: RequestInit = {}) {
  if (testFetch !== undefined) {
    return await testFetch(input, init);
  }
  return await pinnedHttpsFetch(new URL(input.toString()), init, 0);
}

export async function assertPublicHttpsUrl(input: string | URL) {
  const url = new URL(input.toString());
  await validatedAddressForUrl(url);
}

async function pinnedHttpsFetch(
  url: URL,
  init: RequestInit,
  redirectCount: number,
): Promise<Response> {
  if (redirectCount > MAX_REDIRECTS) {
    throw CrmError.network("CRM request redirected too many times");
  }

  const pinned = await validatedAddressForUrl(url);
  const body = requestBody(init.body);
  const headers = headersFromInit(init.headers);
  if (body !== undefined && !hasHeader(headers, "content-length")) {
    headers["content-length"] = String(Buffer.byteLength(body));
  }

  return await new Promise<Response>((resolve, reject) => {
    const options: RequestOptions = {
      protocol: "https:",
      hostname: url.hostname,
      port: url.port === "" ? 443 : Number(url.port),
      path: `${url.pathname}${url.search}`,
      method: init.method ?? "GET",
      headers,
      servername: url.hostname,
      lookup: createPinnedLookup(pinned),
      timeout: 30_000,
    };

    const req = httpsRequest(options, (res) => {
      const status = res.statusCode ?? 0;
      const location = firstHeader(res.headers.location);
      if (status >= 300 && status < 400 && location !== undefined) {
        res.resume();
        const redirectURL = new URL(location, url);
        if (!isSameOriginRedirect(url, redirectURL)) {
          reject(CrmError.network("CRM request redirected to a different origin"));
          return;
        }
        pinnedHttpsFetch(
          redirectURL,
          redirectInit(init, status),
          redirectCount + 1,
        ).then(resolve, reject);
        return;
      }

      const chunks: Buffer[] = [];
      res.on("data", (chunk: Buffer | string) => {
        chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
      });
      res.on("end", () => {
        resolve(
          new Response(Buffer.concat(chunks), {
            status,
            headers: responseHeaders(res.headers),
          }),
        );
      });
    });

    req.on("timeout", () => {
      req.destroy(new Error("CRM request timed out"));
    });
    req.on("error", reject);
    if (body !== undefined) {
      req.write(body);
    }
    req.end();
  });
}

export function createPinnedLookup(pinned: {
  address: string;
  family: 4 | 6;
}): LookupFunction {
  return (_hostname, options, callback) => {
    if (options.all === true) {
      callback(null, [pinned]);
      return;
    }
    callback(null, pinned.address, pinned.family);
  };
}

async function validatedAddressForUrl(url: URL) {
  if (url.protocol !== "https:") {
    throw CrmError.configuration("CRM base URL must use https");
  }
  if (url.username !== "" || url.password !== "") {
    throw CrmError.configuration("CRM base URL must not include credentials");
  }

  const host = normalizedHostname(url.hostname);
  const literalFamily = isIP(host);
  if (literalFamily !== 0) {
    assertPublicAddress(host);
    return { address: host, family: literalFamily as 4 | 6 };
  }

  if (
    host === "localhost" ||
    host.endsWith(".localhost") ||
    host.endsWith(".local") ||
    host.endsWith(".internal") ||
    host.endsWith(".lan") ||
    !host.includes(".")
  ) {
    throw CrmError.configuration("CRM base URL must be publicly reachable");
  }

  let records: Array<{ address: string; family: 4 | 6 }>;
  try {
    records = (await dnsLookup(host, {
      all: true,
      verbatim: true,
    })) as Array<{ address: string; family: 4 | 6 }>;
  } catch (error) {
    throw CrmError.network(
      error instanceof Error
        ? `CRM base URL hostname could not be resolved: ${error.message}`
        : "CRM base URL hostname could not be resolved",
    );
  }

  if (records.length === 0) {
    throw CrmError.network("CRM base URL hostname did not resolve");
  }
  for (const record of records) {
    assertPublicAddress(record.address);
  }
  return records[0];
}

function assertPublicAddress(address: string) {
  if (!isPublicAddress(address)) {
    throw CrmError.configuration("CRM base URL must be publicly reachable");
  }
}

export function isPublicAddress(address: string) {
  const host = normalizedHostname(address);
  if (isIP(host) === 4) {
    return isPublicIPv4(host);
  }
  if (isIP(host) === 6) {
    return isPublicIPv6(host);
  }
  return false;
}

export function isSameOriginRedirect(source: string | URL, target: string | URL) {
  const sourceUrl = new URL(source.toString());
  const targetUrl = new URL(target.toString(), sourceUrl);
  return (
    sourceUrl.protocol === targetUrl.protocol &&
    normalizedHostname(sourceUrl.hostname) === normalizedHostname(targetUrl.hostname) &&
    effectivePort(sourceUrl) === effectivePort(targetUrl)
  );
}

function isPublicIPv4(address: string) {
  const octets = address.split(".").map((part) => Number(part));
  if (
    octets.length !== 4 ||
    octets.some((octet) => !Number.isInteger(octet) || octet < 0 || octet > 255)
  ) {
    return false;
  }
  const [a, b] = octets;
  if (a === undefined || b === undefined) {
    return false;
  }
  return !(
    a === 0 ||
    a === 10 ||
    a === 127 ||
    (a === 100 && b >= 64 && b <= 127) ||
    (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 0) ||
    (a === 192 && b === 168) ||
    (a === 198 && (b === 18 || b === 19)) ||
    (a === 198 && b === 51) ||
    (a === 203 && b === 0) ||
    a >= 224
  );
}

function isPublicIPv6(address: string) {
  const value = ipv6ToBigInt(address);
  if (value === undefined) {
    return false;
  }
  const mapped = ipv4FromMappedIPv6(value);
  if (mapped !== undefined) {
    return isPublicIPv4(mapped);
  }
  return (
    !inIPv6Range(value, "0000:0000:0000:0000:0000:0000:0000:0000", 8) &&
    !inIPv6Range(value, "0064:ff9b:0000:0000:0000:0000:0000:0000", 96) &&
    !inIPv6Range(value, "0100:0000:0000:0000:0000:0000:0000:0000", 64) &&
    !inIPv6Range(value, "2001:0000:0000:0000:0000:0000:0000:0000", 32) &&
    !inIPv6Range(value, "2001:0002:0000:0000:0000:0000:0000:0000", 48) &&
    !inIPv6Range(value, "2001:0db8:0000:0000:0000:0000:0000:0000", 32) &&
    !inIPv6Range(value, "2002:0000:0000:0000:0000:0000:0000:0000", 16) &&
    !inIPv6Range(value, "fc00:0000:0000:0000:0000:0000:0000:0000", 7) &&
    !inIPv6Range(value, "fe80:0000:0000:0000:0000:0000:0000:0000", 10) &&
    !inIPv6Range(value, "ff00:0000:0000:0000:0000:0000:0000:0000", 8)
  );
}

function ipv4FromMappedIPv6(value: bigint) {
  const mappedPrefix = ipv6ToBigInt("0000:0000:0000:0000:0000:ffff:0000:0000");
  if (mappedPrefix === undefined || !inIPv6Range(value, "0000:0000:0000:0000:0000:ffff:0000:0000", 96)) {
    return undefined;
  }
  const ipv4 = Number(value - mappedPrefix);
  return [
    (ipv4 >>> 24) & 255,
    (ipv4 >>> 16) & 255,
    (ipv4 >>> 8) & 255,
    ipv4 & 255,
  ].join(".");
}

function inIPv6Range(value: bigint, baseAddress: string, prefixBits: number) {
  const base = ipv6ToBigInt(baseAddress);
  if (base === undefined) {
    return false;
  }
  const shift = BigInt(128 - prefixBits);
  return value >> shift === base >> shift;
}

function ipv6ToBigInt(address: string) {
  const host = normalizedHostname(address);
  const ipv4Tail = host.match(/(.+):(\d{1,3}(?:\.\d{1,3}){3})$/);
  let normalized = host;
  let tailParts: string[] = [];
  if (ipv4Tail !== null) {
    normalized = ipv4Tail[1] ?? "";
    const octets = (ipv4Tail[2] ?? "").split(".").map((part) => Number(part));
    if (
      octets.length !== 4 ||
      octets.some((octet) => !Number.isInteger(octet) || octet < 0 || octet > 255)
    ) {
      return undefined;
    }
    tailParts = [
      ((octets[0]! << 8) | octets[1]!).toString(16),
      ((octets[2]! << 8) | octets[3]!).toString(16),
    ];
  }

  const sides = normalized.split("::");
  if (sides.length > 2) {
    return undefined;
  }
  const left = splitIPv6Side(sides[0] ?? "");
  const right = splitIPv6Side(sides[1] ?? "");
  if (left === undefined || right === undefined) {
    return undefined;
  }

  const missing = 8 - left.length - right.length - tailParts.length;
  if (sides.length === 1 && missing !== 0) {
    return undefined;
  }
  if (sides.length === 2 && missing < 1) {
    return undefined;
  }
  const parts = [
    ...left,
    ...Array.from({ length: Math.max(0, missing) }, () => "0"),
    ...right,
    ...tailParts,
  ];
  if (parts.length !== 8) {
    return undefined;
  }

  let value = 0n;
  for (const part of parts) {
    const segment = Number.parseInt(part, 16);
    if (!Number.isInteger(segment) || segment < 0 || segment > 0xffff) {
      return undefined;
    }
    value = (value << 16n) + BigInt(segment);
  }
  return value;
}

function splitIPv6Side(value: string) {
  if (value === "") {
    return [];
  }
  const parts = value.split(":");
  return parts.every((part) => /^[0-9a-f]{1,4}$/i.test(part)) ? parts : undefined;
}

function normalizedHostname(hostname: string) {
  return hostname.toLowerCase().replace(/^\[|\]$/g, "").replace(/\.$/, "");
}

function effectivePort(url: URL) {
  if (url.port !== "") {
    return url.port;
  }
  if (url.protocol === "https:") {
    return "443";
  }
  if (url.protocol === "http:") {
    return "80";
  }
  return "";
}

function redirectInit(init: RequestInit, status: number): RequestInit {
  if (status === 303 || ((status === 301 || status === 302) && init.method === "POST")) {
    return {
      ...init,
      method: "GET",
      body: undefined,
    };
  }
  return init;
}

function requestBody(body: BodyInit | null | undefined) {
  if (body === undefined || body === null) {
    return undefined;
  }
  if (typeof body === "string") {
    return body;
  }
  if (body instanceof Uint8Array) {
    return Buffer.from(body);
  }
  throw CrmError.configuration("CRM request body type is unsupported");
}

function headersFromInit(input: HeadersInit | undefined) {
  const output: Record<string, string> = {};
  const headers = new Headers(input);
  headers.forEach((value, key) => {
    output[key] = value;
  });
  return output;
}

function hasHeader(headers: Record<string, string>, name: string) {
  const wanted = name.toLowerCase();
  return Object.keys(headers).some((key) => key.toLowerCase() === wanted);
}

function responseHeaders(headers: IncomingHttpHeaders) {
  const output = new Headers();
  for (const [key, value] of Object.entries(headers)) {
    if (Array.isArray(value)) {
      for (const item of value) {
        output.append(key, item);
      }
    } else if (value !== undefined) {
      output.set(key, value);
    }
  }
  return output;
}

function firstHeader(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}
