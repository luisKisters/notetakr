import { describe, expect, test } from "vitest";
import { isPublicAddress, isSameOriginRedirect } from "./safeFetch";

describe("safe CRM fetch", () => {
  test("classifies public and private IP addresses", () => {
    expect(isPublicAddress("8.8.8.8")).toBe(true);
    expect(isPublicAddress("1.1.1.1")).toBe(true);
    expect(isPublicAddress("10.0.0.1")).toBe(false);
    expect(isPublicAddress("127.0.0.1")).toBe(false);
    expect(isPublicAddress("169.254.1.1")).toBe(false);
    expect(isPublicAddress("172.16.0.1")).toBe(false);
    expect(isPublicAddress("192.168.1.1")).toBe(false);
    expect(isPublicAddress("198.18.0.1")).toBe(false);
    expect(isPublicAddress("2606:4700:4700::1111")).toBe(true);
    expect(isPublicAddress("::1")).toBe(false);
    expect(isPublicAddress("fe80::1")).toBe(false);
    expect(isPublicAddress("fc00::1")).toBe(false);
    expect(isPublicAddress("::ffff:192.168.1.1")).toBe(false);
  });

  test("rejects redirects that would carry credentials to another origin", () => {
    expect(
      isSameOriginRedirect("https://crm.test/api", "https://crm.test/next"),
    ).toBe(true);
    expect(
      isSameOriginRedirect("https://crm.test/api", "https://crm.test:443/next"),
    ).toBe(true);
    expect(
      isSameOriginRedirect("https://crm.test/api", "https://evil.test/next"),
    ).toBe(false);
    expect(
      isSameOriginRedirect("https://crm.test/api", "http://crm.test/next"),
    ).toBe(false);
  });
});
