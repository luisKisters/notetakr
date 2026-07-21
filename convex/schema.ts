import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

const participant = v.object({
  name: v.string(),
  email: v.optional(v.string()),
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

export default defineSchema({
  meetings: defineTable({
    userId: v.string(),
    localId: v.string(),
    title: v.string(),
    startedAt: v.string(),
    calendarEventId: v.optional(v.string()),
    participants: v.array(participant),
    contentHash: v.string(),
    summary: v.optional(v.string()),
    summaryStatus: v.optional(summaryStatus),
    summaryError: v.optional(v.string()),
    crmNoteId: v.optional(v.string()),
    pushStatus: v.optional(pushStatus),
    unmatchedParticipants: v.optional(v.array(participant)),
    crmPushOptOut: v.optional(v.boolean()),
  }).index("by_user_localId", {
    fields: ["userId", "localId"],
  }),

  notes: defineTable({
    userId: v.string(),
    meetingId: v.id("meetings"),
    markdownBody: v.string(),
  }).index("by_meeting", {
    fields: ["meetingId"],
  }),

  transcriptSegments: defineTable({
    userId: v.string(),
    meetingId: v.id("meetings"),
    seq: v.number(),
    startMs: v.number(),
    speaker: v.optional(v.string()),
    text: v.string(),
  }).index("by_meeting", {
    fields: ["meetingId"],
  }),

  people: defineTable({
    userId: v.string(),
    email: v.string(),
    name: v.string(),
    company: v.optional(v.string()),
    provider: v.optional(v.string()),
    remoteId: v.optional(v.string()),
    sourceRefs: v.optional(v.array(v.string())),
  }).index("by_user_email", {
    fields: ["userId", "email"],
  }),

  userSettings: defineTable({
    userId: v.string(),
    openRouterApiKey: v.optional(v.string()),
    crm: v.optional(
      v.object({
        provider: v.string(),
        baseUrl: v.optional(v.string()),
        encryptedApiKey: v.optional(v.string()),
      }),
    ),
  }).index("by_user", {
    fields: ["userId"],
  }),

  devices: defineTable({
    userId: v.string(),
    deviceId: v.string(),
    name: v.optional(v.string()),
    lastSeenAt: v.number(),
  }).index("by_user_device", {
    fields: ["userId", "deviceId"],
  }),
});
