import { v } from "convex/values";
import { internal } from "../_generated/api";
import {
  action,
  internalAction,
  internalMutation,
  internalQuery,
  query,
} from "../_generated/server";
import type { CrmPerson } from "./provider";

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

const connectionState = v.object({
  connected: v.boolean(),
  provider: v.optional(v.string()),
});

const refreshPeopleResult = v.object({
  skipped: v.boolean(),
  inserted: v.number(),
  updated: v.number(),
  removed: v.number(),
  people: v.array(cachedPerson),
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

    const existingProviderRows = await ctx.db
      .query("people")
      .withIndex("by_user_provider", (q) =>
        q.eq("userId", userId).eq("provider", provider),
      )
      .collect();
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
    return await ctx.runAction(internal.crm.network.mirrorUser, {
      userId,
    });
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
        await ctx.runAction(internal.crm.network.mirrorUser, {
          userId: setting.userId,
        });
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
    return await ctx.runAction(internal.crm.network.mirrorUser, { userId });
  },
});

export const currentPeopleSnapshot = query({
  args: {},
  returns: v.array(cachedPerson),
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const rows = (await ctx.db
      .query("people")
      .withIndex("by_user_email", (q) => q.eq("userId", userId))
      .collect()).filter((row) => row.remoteId !== undefined);

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
    const settings = await ctx.db
      .query("userSettings")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .unique();
    const provider = normalizedString(settings?.crm?.provider);
    if (provider === undefined) {
      return [];
    }

    const rows = (await ctx.db
      .query("people")
      .withIndex("by_user_provider", (q) =>
        q.eq("userId", userId).eq("provider", provider),
      )
      .collect()).filter((row) => row.remoteId !== undefined);

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

export const crmConnectionState = action({
  args: {},
  returns: connectionState,
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const crm = await ctx.runQuery(internal.crm.mirror.crmSettingsForUser, {
      userId,
    });
    if (crm === null) {
      return { connected: false };
    }
    return await ctx.runAction(internal.crm.network.crmConnectionState, {
      crm,
    });
  },
});

export const refreshPeople = action({
  args: {},
  returns: refreshPeopleResult,
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const result = await ctx.runAction(internal.crm.network.mirrorUser, {
      userId,
    });
    const people = await ctx.runQuery(internal.crm.mirror.peopleSnapshotForUser, {
      userId,
    });
    return { ...result, people };
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
    return await ctx.runAction(internal.crm.network.testCrmConnection, { crm });
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
    return await ctx.runAction(internal.crm.network.saveCrmConfig, {
      userId,
      crm,
    });
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
