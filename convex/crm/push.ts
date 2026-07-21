import { v } from "convex/values";
import { internal } from "../_generated/api";
import {
  internalAction,
  internalMutation,
  internalQuery,
} from "../_generated/server";
import { requireCrmProvider } from "./provider";
import "./attio";
import "./twenty";

const participant = v.object({
  name: v.string(),
  email: v.optional(v.string()),
});

const transcriptSegment = v.object({
  seq: v.number(),
  startMs: v.number(),
  speaker: v.optional(v.string()),
  text: v.string(),
});

const pushStatus = v.union(
  v.literal("pending"),
  v.literal("pushed"),
  v.literal("failed"),
  v.literal("skipped"),
);

const crmConfig = v.object({
  provider: v.string(),
  baseUrl: v.optional(v.string()),
  apiKey: v.optional(v.string()),
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

type Participant = {
  name: string;
  email?: string;
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
    apiKey?: string;
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

export const loadPushInput = internalQuery({
  args: {
    meetingId: v.id("meetings"),
  },
  returns: v.union(v.null(), pushInput),
  handler: async (ctx, { meetingId }) => {
    const meeting = await ctx.db.get(meetingId);
    if (meeting === null) {
      return null;
    }

    const settings = await ctx.db
      .query("userSettings")
      .withIndex("by_user", (q) => q.eq("userId", meeting.userId))
      .unique();
    const people = (await ctx.db.query("people").collect())
      .filter((person) => person.userId === meeting.userId)
      .filter((person) => person.provider === settings?.crm?.provider)
      .map((person) => ({
        email: person.email,
        remoteId: person.remoteId,
      }));
    const transcriptSegments = await ctx.db
      .query("transcriptSegments")
      .withIndex("by_meeting", (q) => q.eq("meetingId", meetingId))
      .collect();

    return {
      userId: meeting.userId,
      title: meeting.title,
      participants: meeting.participants,
      summary: meeting.summary,
      crmNoteId: meeting.crmNoteId,
      crmPushOptOut: meeting.crmPushOptOut,
      crm: settings?.crm,
      people,
      transcriptSegments: transcriptSegments
        .map((segment) => ({
          seq: segment.seq,
          startMs: segment.startMs,
          speaker: segment.speaker,
          text: segment.text,
        }))
        .sort((a, b) => a.seq - b.seq),
    };
  },
});

export const writePushSkipped = internalMutation({
  args: {
    meetingId: v.id("meetings"),
    unmatchedParticipants: v.array(participant),
  },
  returns: v.null(),
  handler: async (ctx, { meetingId, unmatchedParticipants }) => {
    await ctx.db.patch(meetingId, {
      pushStatus: "skipped",
      unmatchedParticipants,
    });
    return null;
  },
});

export const writePushFailed = internalMutation({
  args: {
    meetingId: v.id("meetings"),
    unmatchedParticipants: v.array(participant),
  },
  returns: v.null(),
  handler: async (ctx, { meetingId, unmatchedParticipants }) => {
    await ctx.db.patch(meetingId, {
      pushStatus: "failed",
      unmatchedParticipants,
    });
    return null;
  },
});

export const writePushPushed = internalMutation({
  args: {
    meetingId: v.id("meetings"),
    crmNoteId: v.string(),
    unmatchedParticipants: v.array(participant),
  },
  returns: v.null(),
  handler: async (ctx, { meetingId, crmNoteId, unmatchedParticipants }) => {
    await ctx.db.patch(meetingId, {
      crmNoteId,
      pushStatus: "pushed",
      unmatchedParticipants,
    });
    return null;
  },
});

export const pushMeetingToCrm = internalAction({
  args: {
    meetingId: v.id("meetings"),
  },
  returns: v.object({
    status: pushStatus,
    skipped: v.boolean(),
  }),
  handler: async (ctx, { meetingId }) => {
    const input = await ctx.runQuery(internal.crm.push.loadPushInput, {
      meetingId,
    });
    if (input === null) {
      return { status: "failed" as const, skipped: false };
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

    const match = matchParticipants(input);
    if (match.personRemoteIds.length === 0) {
      await ctx.runMutation(internal.crm.push.writePushSkipped, {
        meetingId,
        unmatchedParticipants: match.unmatchedParticipants,
      });
      return { status: "skipped" as const, skipped: true };
    }

    try {
      const provider = requireCrmProvider(input.crm.provider);
      const crmNoteId = await provider.upsertMeetingNote(
        input.crm,
        match.personRemoteIds,
        input.title,
        meetingMarkdown(input),
        input.crmNoteId,
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

function matchParticipants(input: PushInput) {
  const remoteIdsByEmail = new Map<string, string[]>();
  for (const person of input.people) {
    const email = normalizedEmail(person.email);
    const remoteId = normalizedString(person.remoteId);
    if (email === undefined || remoteId === undefined) {
      continue;
    }
    const remoteIds = remoteIdsByEmail.get(email) ?? [];
    remoteIds.push(remoteId);
    remoteIdsByEmail.set(email, remoteIds);
  }

  const personRemoteIds: string[] = [];
  const unmatchedParticipants: Participant[] = [];
  for (const participant of input.participants) {
    const email = normalizedEmail(participant.email);
    if (email === undefined) {
      unmatchedParticipants.push({ name: participant.name });
      continue;
    }

    const remoteIds = remoteIdsByEmail.get(email);
    if (remoteIds === undefined || remoteIds.length === 0) {
      unmatchedParticipants.push({
        name: participant.name,
        email,
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
    normalizedString(input.summary) ?? "Summary not available.",
    "",
    "## Transcript",
    transcriptMarkdown(input.transcriptSegments),
  ].join("\n");
}

function transcriptMarkdown(segments: PushInput["transcriptSegments"]) {
  if (segments.length === 0) {
    return "Transcript not available.";
  }
  return segments
    .map((segment) => {
      const text = segment.text.trim();
      const speaker = normalizedString(segment.speaker);
      return speaker === undefined ? text : `${speaker}: ${text}`;
    })
    .join("\n");
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
