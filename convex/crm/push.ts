import { v } from "convex/values";
import { internal } from "../_generated/api";
import {
  internalAction,
  internalMutation,
  internalQuery,
} from "../_generated/server";

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

const pushStatus = v.union(
  v.literal("pending"),
  v.literal("pushed"),
  v.literal("failed"),
  v.literal("skipped"),
);

const crmConfig = v.object({
  provider: v.string(),
  baseUrl: v.optional(v.string()),
  encryptedApiKey: v.optional(v.string()),
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
    return await ctx.runAction(internal.crm.network.pushMeetingToCrm, {
      meetingId,
    });
  },
});
