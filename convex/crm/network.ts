"use node";

import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, type ActionCtx } from "../_generated/server";
import {
  CrmError,
  type CrmConfig,
  requireCrmProvider,
} from "./provider";
import { assertPublicHttpsUrl } from "./safeFetch";
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

const crmConfig = v.object({
  provider: v.string(),
  baseUrl: v.optional(v.string()),
  encryptedApiKey: v.optional(v.string()),
});

const participant = v.object({
  name: v.string(),
  email: v.optional(v.string()),
  crm: v.optional(v.string()),
});

const transcriptSegment = v.object({
  seq: v.number(),
  startMs: v.number(),
  speaker: v.optional(v.string()),
  text: v.string(),
});

const pushInput = v.object({
  userId: v.string(),
  title: v.string(),
  participants: v.array(participant),
  summary: v.optional(v.string()),
  crmNoteId: v.optional(v.string()),
  crmPushOptOut: v.optional(v.boolean()),
  crm: v.optional(crmConfig),
  people: v.array(
    v.object({
      email: v.string(),
      remoteId: v.optional(v.string()),
    }),
  ),
  transcriptSegments: v.array(transcriptSegment),
});

const mirrorResult = v.object({
  skipped: v.boolean(),
  inserted: v.number(),
  updated: v.number(),
  removed: v.number(),
});

const connectionState = v.object({
  connected: v.boolean(),
  provider: v.optional(v.string()),
});

const pushResult = v.object({
  status: v.union(
    v.literal("pushed"),
    v.literal("skipped"),
    v.literal("failed"),
  ),
  skipped: v.boolean(),
});

type Participant = {
  name: string;
  email?: string;
  crm?: string;
};

type PushInput = {
  userId: string;
  title: string;
  participants: Participant[];
  summary?: string;
  crmNoteId?: string;
  crmPushOptOut?: boolean;
  crm?: {
    provider: string;
    baseUrl?: string;
    encryptedApiKey?: string;
  };
  people: Array<{
    email: string;
    remoteId?: string;
  }>;
  transcriptSegments: Array<{
    seq: number;
    startMs: number;
    speaker?: string;
    text: string;
  }>;
};

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

export const testCrmConnection = internalAction({
  args: {
    crm: crmInputConfig,
  },
  returns: v.object({
    ok: v.boolean(),
    code: v.optional(v.string()),
    message: v.optional(v.string()),
  }),
  handler: async (_ctx, { crm }) => {
    try {
      await validateCrmConfig(crm);
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

export const crmConnectionState = internalAction({
  args: {
    crm: crmConfig,
  },
  returns: connectionState,
  handler: async (_ctx, { crm }) => {
    try {
      const materialized = await materializeCrmConfig(crm);
      await validateCrmConfig(materialized);
      const provider = requireCrmProvider(materialized.provider);
      await provider.listPeople(materialized);
      return { connected: true, provider: materialized.provider };
    } catch {
      return { connected: false };
    }
  },
});

export const saveCrmConfig = internalAction({
  args: {
    userId: v.string(),
    crm: crmInputConfig,
  },
  returns: v.object({
    scheduledMirror: v.boolean(),
  }),
  handler: async (ctx, { userId, crm }) => {
    await validateCrmConfig(crm);
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

export const pushMeetingToCrm = internalAction({
  args: {
    meetingId: v.id("meetings"),
  },
  returns: pushResult,
  handler: async (ctx, { meetingId }) => {
    const input = await ctx.runQuery(internal.crm.push.loadPushInput, {
      meetingId,
    });
    if (input === null) {
      return { status: "skipped" as const, skipped: true };
    }

    if (input.crmPushOptOut === true) {
      await ctx.runMutation(internal.crm.push.writePushSkipped, {
        meetingId,
        unmatchedParticipants: [],
      });
      return { status: "skipped" as const, skipped: true };
    }

    if (input.crm === undefined) {
      await ctx.runMutation(internal.crm.push.writePushSkipped, {
        meetingId,
        unmatchedParticipants: [],
      });
      return { status: "skipped" as const, skipped: true };
    }

    let pushInput = input;
    let match = matchParticipants(pushInput);
    if (match.personRemoteIds.length === 0) {
      try {
        await mirrorUserWithConfig(ctx, input.userId, input.crm as StoredCrmConfig);
        const refreshed = await ctx.runQuery(internal.crm.push.loadPushInput, {
          meetingId,
        });
        if (refreshed !== null) {
          if (refreshed.crmPushOptOut === true) {
            await ctx.runMutation(internal.crm.push.writePushSkipped, {
              meetingId,
              unmatchedParticipants: [],
            });
            return { status: "skipped" as const, skipped: true };
          }
          if (refreshed.crm === undefined) {
            await ctx.runMutation(internal.crm.push.writePushSkipped, {
              meetingId,
              unmatchedParticipants: [],
            });
            return { status: "skipped" as const, skipped: true };
          }
          pushInput = refreshed;
          match = matchParticipants(pushInput);
        }
      } catch {
        await ctx.runMutation(internal.crm.push.writePushFailed, {
          meetingId,
          unmatchedParticipants: match.unmatchedParticipants,
        });
        return { status: "failed" as const, skipped: false };
      }
    }

    if (match.personRemoteIds.length === 0) {
      await ctx.runMutation(internal.crm.push.writePushSkipped, {
        meetingId,
        unmatchedParticipants: match.unmatchedParticipants,
      });
      return { status: "skipped" as const, skipped: true };
    }

    try {
      const crm = await materializeCrmConfig(pushInput.crm as StoredCrmConfig);
      await validateCrmConfig(crm);
      const provider = requireCrmProvider(crm.provider);
      const crmNoteId = await provider.upsertMeetingNote(
        crm,
        match.personRemoteIds,
        pushInput.title,
        meetingMarkdown(pushInput),
        pushInput.crmNoteId,
      );

      await ctx.runMutation(internal.crm.push.writePushPushed, {
        meetingId,
        crmNoteId,
        unmatchedParticipants: match.unmatchedParticipants,
      });
      return { status: "pushed" as const, skipped: false };
    } catch {
      await ctx.runMutation(internal.crm.push.writePushFailed, {
        meetingId,
        unmatchedParticipants: match.unmatchedParticipants,
      });
      return { status: "failed" as const, skipped: false };
    }
  },
});

async function mirrorUserWithConfig(
  ctx: ActionCtx,
  userId: string,
  storedCrm: StoredCrmConfig,
) {
  const crm = await materializeCrmConfig(storedCrm);
  await validateCrmConfig(crm);
  const provider = requireCrmProvider(crm.provider);
  const people = await provider.listPeople(crm);
  const result = await ctx.runMutation(internal.crm.mirror.applyMirror, {
    userId,
    provider: crm.provider,
    people,
  });
  return { skipped: false, ...result };
}

async function validateCrmConfig(crm: CrmConfig) {
  if (normalizedString(crm.apiKey) === undefined) {
    throw CrmError.configuration("CRM API key is not configured");
  }
  const baseUrl = normalizedString(crm.baseUrl);
  if (baseUrl !== undefined && isBuiltInProvider(crm.provider)) {
    await assertPublicHttpsUrl(baseUrl);
  }
}

function isBuiltInProvider(provider: string) {
  return provider === "twenty" || provider === "attio";
}

function matchParticipants(input: PushInput) {
  const remoteIdsByEmail = new Map<string, string[]>();
  const knownRemoteIds = new Set<string>();
  for (const person of input.people) {
    const email = normalizedEmail(person.email);
    const remoteId = normalizedString(person.remoteId);
    if (remoteId === undefined) {
      continue;
    }
    knownRemoteIds.add(remoteId);
    if (email === undefined) {
      continue;
    }
    const remoteIds = remoteIdsByEmail.get(email) ?? [];
    remoteIds.push(remoteId);
    remoteIdsByEmail.set(email, remoteIds);
  }

  const personRemoteIds: string[] = [];
  const unmatchedParticipants: Participant[] = [];
  for (const participant of input.participants) {
    const crmRemoteId = normalizedString(participant.crm);
    if (crmRemoteId !== undefined && knownRemoteIds.has(crmRemoteId)) {
      personRemoteIds.push(crmRemoteId);
      continue;
    }

    const email = normalizedEmail(participant.email);
    if (email === undefined) {
      unmatchedParticipants.push({
        name: participant.name,
        ...(crmRemoteId === undefined ? {} : { crm: crmRemoteId }),
      });
      continue;
    }

    const remoteIds = remoteIdsByEmail.get(email);
    if (remoteIds === undefined || remoteIds.length === 0) {
      unmatchedParticipants.push({
        name: participant.name,
        email,
        ...(crmRemoteId === undefined ? {} : { crm: crmRemoteId }),
      });
      continue;
    }

    personRemoteIds.push(...remoteIds);
  }

  return {
    personRemoteIds: unique(personRemoteIds),
    unmatchedParticipants,
  };
}

function meetingMarkdown(input: PushInput) {
  return [
    `# ${input.title}`,
    "",
    "## Summary",
    "",
    input.summary ?? "",
    "",
    "## Transcript",
    "",
    ...input.transcriptSegments
      .slice()
      .sort((a, b) => a.seq - b.seq)
      .map((segment) => {
        const speaker = normalizedString(segment.speaker);
        return speaker === undefined ? segment.text : `${speaker}: ${segment.text}`;
      }),
  ].join("\n");
}

function unique(values: string[]) {
  return Array.from(new Set(values));
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
