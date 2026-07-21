import { v } from "convex/values";
import { internal } from "../_generated/api";
import {
  action,
  internalAction,
  internalMutation,
  internalQuery,
  mutation,
  type ActionCtx,
} from "../_generated/server";
import {
  type CrmConfig,
  type CrmPerson,
  requireCrmProvider,
} from "./provider";
import "./twenty";

const crmConfig = v.object({
  provider: v.string(),
  baseUrl: v.optional(v.string()),
  apiKey: v.optional(v.string()),
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
  returns: v.union(v.null(), crmConfig),
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
      crm: crmConfig,
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

export const saveCrmConfig = mutation({
  args: {
    crm: crmConfig,
  },
  returns: v.object({
    scheduledMirror: v.boolean(),
  }),
  handler: async (ctx, { crm }) => {
    const userId = await requireUserId(ctx);
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
    return { scheduledMirror: true };
  },
});

async function mirrorUserWithConfig(
  ctx: ActionCtx,
  userId: string,
  crm: CrmConfig,
) {
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
