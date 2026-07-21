import { makeFunctionReference } from "convex/server";
import { v } from "convex/values";
import { mutation, query } from "./_generated/server";

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

const meetingPayload = v.object({
  localId: v.string(),
  title: v.string(),
  startedAt: v.string(),
  calendarEventId: v.optional(v.string()),
  participants: v.array(participant),
  markdownBody: v.string(),
  transcriptSegments: v.array(transcriptSegment),
  crmPushOptOut: v.optional(v.boolean()),
  contentHash: v.string(),
});

const summaryStatus = v.union(
  v.literal("pending"),
  v.literal("ready"),
  v.literal("failed"),
);

const pushStatus = v.union(
  v.literal("pending"),
  v.literal("pushed"),
  v.literal("failed"),
  v.literal("skipped"),
);

const summarizeMeeting = makeFunctionReference<"action">(
  "summarize:summarizeMeeting",
);

async function requireUserId(ctx: { auth: { getUserIdentity: () => Promise<{ subject: string } | null> } }) {
  const identity = await ctx.auth.getUserIdentity();
  if (identity === null) {
    throw new Error("Authentication required");
  }
  return identity.subject;
}

export const upsertFromDevice = mutation({
  args: {
    payload: meetingPayload,
  },
  returns: v.object({
    meetingId: v.id("meetings"),
    scheduledSummary: v.boolean(),
  }),
  handler: async (ctx, { payload }) => {
    const userId = await requireUserId(ctx);

    const existing = await ctx.db
      .query("meetings")
      .withIndex("by_user_localId", (q) =>
        q.eq("userId", userId).eq("localId", payload.localId),
      )
      .unique();

    const hasTranscript = payload.transcriptSegments.length > 0;
    const contentChanged =
      existing === null || existing.contentHash !== payload.contentHash;
    const shouldScheduleSummary = hasTranscript && contentChanged;

    let meetingId = existing?._id;
    const meetingFields = {
      userId,
      localId: payload.localId,
      title: payload.title,
      startedAt: payload.startedAt,
      calendarEventId: payload.calendarEventId,
      participants: payload.participants,
      contentHash: payload.contentHash,
      crmPushOptOut: payload.crmPushOptOut,
      summaryStatus: shouldScheduleSummary
        ? ("pending" as const)
        : existing?.summaryStatus,
      summaryError: shouldScheduleSummary ? undefined : existing?.summaryError,
    };

    if (meetingId === undefined) {
      meetingId = await ctx.db.insert("meetings", meetingFields);
    } else {
      await ctx.db.patch(meetingId, meetingFields);
    }

    const existingNote = await ctx.db
      .query("notes")
      .withIndex("by_meeting", (q) => q.eq("meetingId", meetingId))
      .unique();

    if (existingNote === null) {
      await ctx.db.insert("notes", {
        userId,
        meetingId,
        markdownBody: payload.markdownBody,
      });
    } else {
      await ctx.db.patch(existingNote._id, {
        userId,
        markdownBody: payload.markdownBody,
      });
    }

    const existingSegments = await ctx.db
      .query("transcriptSegments")
      .withIndex("by_meeting", (q) => q.eq("meetingId", meetingId))
      .collect();
    for (const segment of existingSegments) {
      await ctx.db.delete(segment._id);
    }
    for (const segment of payload.transcriptSegments) {
      await ctx.db.insert("transcriptSegments", {
        userId,
        meetingId,
        ...segment,
      });
    }

    if (shouldScheduleSummary) {
      await ctx.scheduler.runAfter(0, summarizeMeeting, { meetingId });
    }

    return { meetingId, scheduledSummary: shouldScheduleSummary };
  },
});

export const getByLocalId = query({
  args: {
    localId: v.string(),
  },
  handler: async (ctx, { localId }) => {
    const userId = await requireUserId(ctx);
    return await ctx.db
      .query("meetings")
      .withIndex("by_user_localId", (q) =>
        q.eq("userId", userId).eq("localId", localId),
      )
      .unique();
  },
});

export const readySummaries = query({
  args: {},
  returns: v.array(
    v.object({
      localId: v.string(),
      summary: v.optional(v.string()),
      summaryStatus: v.optional(summaryStatus),
      summaryError: v.optional(v.string()),
      pushStatus: v.optional(pushStatus),
    }),
  ),
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const meetings = await ctx.db.query("meetings").collect();
    return meetings
      .filter((meeting) => meeting.userId === userId)
      .filter((meeting) => meeting.summaryStatus === "ready")
      .map((meeting) => ({
        localId: meeting.localId,
        summary: meeting.summary,
        summaryStatus: meeting.summaryStatus,
        ...(meeting.summaryError === undefined ? {} : { summaryError: meeting.summaryError }),
        ...(meeting.pushStatus === undefined ? {} : { pushStatus: meeting.pushStatus }),
      }));
  },
});

export const summaryUpdates = query({
  args: {},
  returns: v.array(
    v.object({
      localId: v.string(),
      summary: v.optional(v.string()),
      summaryStatus: v.optional(summaryStatus),
      summaryError: v.optional(v.string()),
      pushStatus: v.optional(pushStatus),
    }),
  ),
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const meetings = await ctx.db.query("meetings").collect();
    return meetings
      .filter((meeting) => meeting.userId === userId)
      .filter((meeting) => meeting.summaryStatus === "ready" || meeting.summaryStatus === "failed")
      .map((meeting) => ({
        localId: meeting.localId,
        summary: meeting.summary,
        summaryStatus: meeting.summaryStatus,
        ...(meeting.summaryError === undefined ? {} : { summaryError: meeting.summaryError }),
        ...(meeting.pushStatus === undefined ? {} : { pushStatus: meeting.pushStatus }),
      }));
  },
});
