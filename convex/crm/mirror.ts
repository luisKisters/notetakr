import { v } from "convex/values";
import { internal } from "../_generated/api";
import {
  action,
  internalAction,
  internalMutation,
  internalQuery,
  mutation,
  query,
  type ActionCtx,
} from "../_generated/server";
import {
  CrmError,
  type CrmConfig,
  type CrmPerson,
  requireCrmProvider,
} from "./provider";
import {
  materializeCrmConfig,
  storedCrmConfigFromInput,
  type StoredCrmConfig,
} from "./secrets";
import "./attio";
import "./twenty";

const crmInputConfig = v.object({
  provider: v.string(),
  baseUrl: v.optional(v.string()),
  apiKey: v.optional(v.string()),
});

const storedCrmConfig = v.object({
  provider: v.string(),
  baseUrl: v.optional(v.string()),
  encryptedApiKey: v.optional(v.string()),
});

const crmPerson = v.object({
  remoteId: v.string(),
  name: v.string(),
  email: v.string(),
  company: v.optional(v.string()),
});

const mirrorResult = v.object({
  skipped: v.boolean(),
  inserted: v.number(),
  updated: v.number(),
  removed: v.number(),
});

const cachedPerson = v.object({
  remoteId: v.string(),
  name: v.string(),
  emails: v.array(v.string()),
  company: v.optional(v.string()),
});

async function requireUserId(ctx: {
  auth: { getUserIdentity: () => Promise<{ subject: string } | null> };
}) {
  const identity = await ctx.auth.getUserIdentity();
  if (identity === null) {
    throw new Error("Authentication required");
  }
  return identity.subject;
}

export const crmSettingsForUser = internalQuery({
  args: {
    userId: v.string(),
  },
  returns: v.union(v.null(), storedCrmConfig),
  handler: async (ctx, { userId }) => {
    const settings = await ctx.db
      .query("userSettings")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .unique();
    return settings?.crm ?? null;
  },
});

export const usersWithCrmSettings = internalQuery({
  args: {},
  returns: v.array(
    v.object({
      userId: v.string(),
      crm: storedCrmConfig,
    }),
  ),
  handler: async (ctx) => {
    const settings = await ctx.db.query("userSettings").collect();
    return settings
      .filter((row) => row.crm !== undefined)
      .map((row) => ({
        userId: row.userId,
        crm: row.crm!,
      }));
  },
});

export const applyMirror = internalMutation({
  args: {
    userId: v.string(),
    provider: v.string(),
    people: v.array(crmPerson),
  },
  returns: v.object({
    inserted: v.number(),
    updated: v.number(),
    removed: v.number(),
  }),
  handler: async (ctx, { userId, provider, people }) => {
    let inserted = 0;
    let updated = 0;
    let removed = 0;
    const incomingByEmail = new Map<string, CrmPerson>();
    const incomingKeys = new Set<string>();

    for (const person of people) {
      const email = normalizedEmail(person.email);
      const remoteId = normalizedString(person.remoteId);
      if (email === undefined || remoteId === undefined) {
        continue;
      }
      const normalizedPerson = {
        ...person,
        email,
        remoteId,
        name: normalizedString(person.name) ?? email,
        company: normalizedString(person.company),
      };
      incomingByEmail.set(email, normalizedPerson);
      incomingKeys.add(mirrorKey(remoteId, email));
    }

    for (const [email, person] of incomingByEmail) {
      const existing = await ctx.db
        .query("people")
        .withIndex("by_user_email", (q) =>
          q.eq("userId", userId).eq("email", email),
        )
        .unique();
      const fields = {
        userId,
        email,
        name: person.name,
        company: person.company,
        provider,
        remoteId: person.remoteId,
        sourceRefs: [`crm:${provider}:${person.remoteId}`],
      };

      if (existing === null) {
        await ctx.db.insert("people", fields);
        inserted += 1;
      } else if (
        existing.name !== fields.name ||
        existing.company !== fields.company ||
        existing.provider !== fields.provider ||
        existing.remoteId !== fields.remoteId ||
        JSON.stringify(existing.sourceRefs ?? []) !==
          JSON.stringify(fields.sourceRefs)
      ) {
        await ctx.db.patch(existing._id, fields);
        updated += 1;
      }
    }

    const existingProviderRows = (await ctx.db.query("people").collect())
      .filter((row) => row.userId === userId)
      .filter((row) => row.provider === provider);
    for (const row of existingProviderRows) {
      if (
        row.remoteId === undefined ||
        !incomingKeys.has(mirrorKey(row.remoteId, row.email))
      ) {
        await ctx.db.delete(row._id);
        removed += 1;
      }
    }

    return { inserted, updated, removed };
  },
});

export const mirrorUser = internalAction({
  args: {
    userId: v.string(),
  },
  returns: mirrorResult,
  handler: async (ctx, { userId }) => {
    const crm = await ctx.runQuery(internal.crm.mirror.crmSettingsForUser, {
      userId,
    });
    if (crm === null) {
      return { skipped: true, inserted: 0, updated: 0, removed: 0 };
    }
    return await mirrorUserWithConfig(ctx, userId, crm);
  },
});

export const mirrorAllUsers = internalAction({
  args: {},
  returns: v.object({
    mirroredUsers: v.number(),
    failedUsers: v.number(),
  }),
  handler: async (ctx) => {
    const settings = await ctx.runQuery(
      internal.crm.mirror.usersWithCrmSettings,
      {},
    );
    let mirroredUsers = 0;
    let failedUsers = 0;

    for (const setting of settings) {
      try {
        await mirrorUserWithConfig(ctx, setting.userId, setting.crm);
        mirroredUsers += 1;
      } catch {
        failedUsers += 1;
      }
    }

    return { mirroredUsers, failedUsers };
  },
});

export const mirrorCurrentUser = action({
  args: {},
  returns: mirrorResult,
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const crm = await ctx.runQuery(internal.crm.mirror.crmSettingsForUser, {
      userId,
    });
    if (crm === null) {
      return { skipped: true, inserted: 0, updated: 0, removed: 0 };
    }
    return await mirrorUserWithConfig(ctx, userId, crm);
  },
});

export const currentPeopleSnapshot = query({
  args: {},
  returns: v.array(cachedPerson),
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const rows = (await ctx.db.query("people").collect())
      .filter((row) => row.userId === userId)
      .filter((row) => row.remoteId !== undefined);

    const grouped = new Map<
      string,
      { remoteId: string; name: string; emails: Set<string>; company?: string }
    >();
    for (const row of rows) {
      const remoteId = normalizedString(row.remoteId);
      const email = normalizedEmail(row.email);
      if (remoteId === undefined || email === undefined) {
        continue;
      }
      const existing = grouped.get(remoteId) ?? {
        remoteId,
        name: normalizedString(row.name) ?? email,
        emails: new Set<string>(),
        company: normalizedString(row.company),
      };
      existing.emails.add(email);
      if (existing.company === undefined) {
        existing.company = normalizedString(row.company);
      }
      grouped.set(remoteId, existing);
    }

    return Array.from(grouped.values())
      .map((person) => ({
        remoteId: person.remoteId,
        name: person.name,
        emails: Array.from(person.emails).sort(),
        company: person.company,
      }))
      .sort((a, b) => a.name.localeCompare(b.name) || a.remoteId.localeCompare(b.remoteId));
  },
});

export const peopleSnapshotForUser = internalQuery({
  args: {
    userId: v.string(),
  },
  returns: v.array(cachedPerson),
  handler: async (ctx, { userId }) => {
    const rows = (await ctx.db.query("people").collect())
      .filter((row) => row.userId === userId)
      .filter((row) => row.remoteId !== undefined);

    const grouped = new Map<
      string,
      { remoteId: string; name: string; emails: Set<string>; company?: string }
    >();
    for (const row of rows) {
      const remoteId = normalizedString(row.remoteId);
      const email = normalizedEmail(row.email);
      if (remoteId === undefined || email === undefined) {
        continue;
      }
      const existing = grouped.get(remoteId) ?? {
        remoteId,
        name: normalizedString(row.name) ?? email,
        emails: new Set<string>(),
        company: normalizedString(row.company),
      };
      existing.emails.add(email);
      if (existing.company === undefined) {
        existing.company = normalizedString(row.company);
      }
      grouped.set(remoteId, existing);
    }

    return Array.from(grouped.values())
      .map((person) => ({
        remoteId: person.remoteId,
        name: person.name,
        emails: Array.from(person.emails).sort(),
        company: person.company,
      }))
      .sort((a, b) => a.name.localeCompare(b.name) || a.remoteId.localeCompare(b.remoteId));
  },
});

export const fetchCurrentPeopleSnapshot = action({
  args: {},
  returns: v.array(cachedPerson),
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    return await ctx.runQuery(internal.crm.mirror.peopleSnapshotForUser, {
      userId,
    });
  },
});

export const refreshPeople = mutation({
  args: {},
  returns: v.object({
    scheduled: v.boolean(),
  }),
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    await ctx.scheduler.runAfter(0, internal.crm.mirror.mirrorUser, {
      userId,
    });
    return { scheduled: true };
  },
});

export const testCrmConnection = action({
  args: {
    crm: crmInputConfig,
  },
  returns: v.object({
    ok: v.boolean(),
    code: v.optional(v.string()),
    message: v.optional(v.string()),
  }),
  handler: async (ctx, { crm }) => {
    await requireUserId(ctx);
    try {
      validateCrmConfig(crm);
      const provider = requireCrmProvider(crm.provider);
      await provider.listPeople(crm);
      return { ok: true };
    } catch (error) {
      if (error instanceof CrmError) {
        return {
          ok: false,
          code: error.code,
          message: error.message,
        };
      }
      return {
        ok: false,
        code: "api_error",
        message: error instanceof Error ? error.message : "CRM connection failed",
      };
    }
  },
});

export const saveCrmConfig = action({
  args: {
    crm: crmInputConfig,
  },
  returns: v.object({
    scheduledMirror: v.boolean(),
  }),
  handler: async (ctx, { crm }) => {
    const userId = await requireUserId(ctx);
    validateCrmConfig(crm);
    const provider = requireCrmProvider(crm.provider);
    await provider.listPeople(crm);
    const storedCrm = await storedCrmConfigFromInput(crm);

    await ctx.runMutation(internal.crm.mirror.writeCrmConfig, {
      userId,
      crm: storedCrm,
    });
    return { scheduledMirror: true };
  },
});

export const writeCrmConfig = internalMutation({
  args: {
    userId: v.string(),
    crm: storedCrmConfig,
  },
  returns: v.null(),
  handler: async (ctx, { userId, crm }) => {
    const existing = await ctx.db
      .query("userSettings")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .unique();

    if (existing === null) {
      await ctx.db.insert("userSettings", { userId, crm });
    } else {
      await ctx.db.patch(existing._id, { crm });
    }

    await ctx.scheduler.runAfter(0, internal.crm.mirror.mirrorUser, {
      userId,
    });
    return null;
  },
});

async function mirrorUserWithConfig(
  ctx: ActionCtx,
  userId: string,
  storedCrm: StoredCrmConfig,
) {
  const crm = await materializeCrmConfig(storedCrm);
  validateCrmConfig(crm);
  const provider = requireCrmProvider(crm.provider);
  const people = await provider.listPeople(crm);
  const result = await ctx.runMutation(internal.crm.mirror.applyMirror, {
    userId,
    provider: crm.provider,
    people,
  });
  return { skipped: false, ...result };
}

function mirrorKey(remoteId: string, email: string) {
  return `${remoteId}\n${email.toLowerCase()}`;
}

function normalizedEmail(value: unknown) {
  return normalizedString(value)?.toLowerCase();
}

function normalizedString(value: unknown) {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed === "" ? undefined : trimmed;
}

function validateCrmConfig(crm: CrmConfig) {
  if (normalizedString(crm.apiKey) === undefined) {
    throw CrmError.configuration("CRM API key is not configured");
  }
  const baseUrl = normalizedString(crm.baseUrl);
  if (baseUrl !== undefined) {
    validatePublicHttpsUrl(baseUrl);
  }
}

function validatePublicHttpsUrl(value: string) {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw CrmError.configuration("CRM base URL is not valid");
  }

  if (url.protocol !== "https:") {
    throw CrmError.configuration("CRM base URL must use https");
  }
  if (isPrivateHost(url.hostname)) {
    throw CrmError.configuration("CRM base URL must be publicly reachable");
  }
}

function isPrivateHost(hostname: string) {
  const host = hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (host === "localhost" || host.endsWith(".localhost")) {
    return true;
  }
  if (host === "::1" || host.startsWith("fe80:") || host.startsWith("fc") || host.startsWith("fd")) {
    return true;
  }

  const ipv4 = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (ipv4 === null) {
    return false;
  }
  const octets = ipv4.slice(1).map((part) => Number(part));
  if (octets.some((octet) => !Number.isInteger(octet) || octet < 0 || octet > 255)) {
    return true;
  }
  const [a, b] = octets;
  return (
    a === 0 ||
    a === 10 ||
    a === 127 ||
    (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168)
  );
}
