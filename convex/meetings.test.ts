import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import { afterEach, describe, expect, test, vi } from "vitest";
import schema from "./schema";

const modules = import.meta.glob("./**/*.*s");

const upsertFromDevice =
  makeFunctionReference<"mutation">("meetings:upsertFromDevice");
const getByLocalId = makeFunctionReference<"query">("meetings:getByLocalId");
const readySummaries =
  makeFunctionReference<"query">("meetings:readySummaries");
const summaryUpdates =
  makeFunctionReference<"query">("meetings:summaryUpdates");

type Segment = {
  seq: number;
  startMs: number;
  speaker?: string;
  text: string;
};

function payload(
  overrides: Partial<{
    localId: string;
    title: string;
    startedAt: string;
    calendarEventId: string;
    participants: Array<{ name: string; email?: string; crm?: string }>;
    markdownBody: string;
    transcriptSegments: Segment[];
    crmPushOptOut: boolean;
    contentHash: string;
  }> = {},
) {
  return {
    localId: "meeting-1",
    title: "Weekly Review",
    startedAt: "2026-07-20T16:00:00Z",
    calendarEventId: "calendar-event-1",
    participants: [
      { name: "Ada Lovelace", email: "ada@example.com" },
      { name: "Grace Hopper", email: "grace@example.com" },
    ],
    markdownBody: "Initial meeting notes",
    transcriptSegments: [
      { seq: 0, startMs: 0, speaker: "Ada", text: "Hello." },
      { seq: 1, startMs: 1200, speaker: "Grace", text: "Hi." },
    ],
    crmPushOptOut: false,
    contentHash: "hash-1",
    ...overrides,
  };
}

function authedTest() {
  return convexTest({ schema, modules }).withIdentity({
    issuer: "https://clerk.test",
    subject: "user-a",
    tokenIdentifier: "user-a",
  });
}

async function allRows(t: ReturnType<typeof authedTest>) {
  return await t.run(async (ctx) => {
    const meetings = await ctx.db.query("meetings").collect();
    const notes = await ctx.db.query("notes").collect();
    const transcriptSegments = await ctx.db
      .query("transcriptSegments")
      .collect();
    const scheduled = await ctx.db.system
      .query("_scheduled_functions")
      .collect();
    return { meetings, notes, transcriptSegments, scheduled };
  });
}

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
});

describe("meetings", () => {
  test("upsert twice with same localId yields one document with updated fields", async () => {
    vi.useFakeTimers();
    const t = authedTest();

    await t.mutation(upsertFromDevice, { payload: payload() });
    await t.mutation(upsertFromDevice, {
      payload: payload({
        title: "Updated Weekly Review",
        markdownBody: "Updated meeting notes",
        contentHash: "hash-2",
      }),
    });

    const rows = await allRows(t);
    expect(rows.meetings).toHaveLength(1);
    expect(rows.meetings[0].title).toBe("Updated Weekly Review");
    expect(rows.meetings[0].contentHash).toBe("hash-2");
    expect(rows.meetings[0].crmPushOptOut).toBe(false);
    expect(rows.notes).toHaveLength(1);
    expect(rows.notes[0].markdownBody).toBe("Updated meeting notes");
  });

  test("upsert persists crmPushOptOut from device payload", async () => {
    vi.useFakeTimers();
    const t = authedTest();

    await t.mutation(upsertFromDevice, {
      payload: payload({ crmPushOptOut: true }),
    });

    await expect(t.query(getByLocalId, { localId: "meeting-1" })).resolves.toMatchObject({
      crmPushOptOut: true,
    });
  });

  test("re-enabling crm push with ready summary schedules crm push without resummarizing", async () => {
    vi.useFakeTimers();
    const t = authedTest();

    const { meetingId } = await t.mutation(upsertFromDevice, {
      payload: payload({ crmPushOptOut: true }),
    });
    await t.run(async (ctx) => {
      await ctx.db.patch(meetingId, {
        summary: "Ready summary",
        summaryStatus: "ready",
        pushStatus: "skipped",
      });
    });

    const result = await t.mutation(upsertFromDevice, {
      payload: payload({ crmPushOptOut: false }),
    });

    const rows = await allRows(t);
    expect(result.scheduledSummary).toBe(false);
    expect(rows.scheduled.map((job) => job.name)).toEqual([
      "summarize:summarizeMeeting",
      "crm/push:pushMeetingToCrm",
    ]);
  });

  test("upsert persists participant crm remote ids from device payload", async () => {
    vi.useFakeTimers();
    const t = authedTest();

    await t.mutation(upsertFromDevice, {
      payload: payload({
        participants: [
          { name: "Ada Lovelace", email: "ada@example.com", crm: "person-1" },
          { name: "Manual Match", crm: "person-2" },
        ],
      }),
    });

    await expect(t.query(getByLocalId, { localId: "meeting-1" })).resolves.toMatchObject({
      participants: [
        { name: "Ada Lovelace", email: "ada@example.com", crm: "person-1" },
        { name: "Manual Match", crm: "person-2" },
      ],
    });
  });

  test("upsert replaces transcript segments, never duplicates", async () => {
    vi.useFakeTimers();
    const t = authedTest();

    await t.mutation(upsertFromDevice, {
      payload: payload({
        transcriptSegments: [
          { seq: 0, startMs: 0, text: "One" },
          { seq: 1, startMs: 1000, text: "Two" },
          { seq: 2, startMs: 2000, text: "Three" },
        ],
      }),
    });
    await t.mutation(upsertFromDevice, {
      payload: payload({
        contentHash: "hash-2",
        transcriptSegments: [
          { seq: 0, startMs: 0, text: "One" },
          { seq: 1, startMs: 1000, text: "Two" },
          { seq: 2, startMs: 2000, text: "Three" },
          { seq: 3, startMs: 3000, text: "Four" },
        ],
      }),
    });

    const rows = await allRows(t);
    expect(rows.transcriptSegments).toHaveLength(4);
    expect(rows.transcriptSegments.map((segment) => segment.seq).sort()).toEqual(
      [0, 1, 2, 3],
    );
  });

  test("unchanged contentHash does not reschedule summarize", async () => {
    vi.useFakeTimers();
    const t = authedTest();

    await t.mutation(upsertFromDevice, { payload: payload() });
    await t.mutation(upsertFromDevice, {
      payload: payload({ title: "Retitled", markdownBody: "Retitled notes" }),
    });

    const rows = await allRows(t);
    expect(rows.scheduled).toHaveLength(1);
    expect(rows.scheduled[0].name).toBe("summarize:summarizeMeeting");
  });

  test("changed contentHash reschedules summarize", async () => {
    vi.useFakeTimers();
    const t = authedTest();

    await t.mutation(upsertFromDevice, { payload: payload() });
    await t.mutation(upsertFromDevice, {
      payload: payload({ contentHash: "hash-2", markdownBody: "Changed" }),
    });

    const rows = await allRows(t);
    expect(rows.scheduled).toHaveLength(2);
    expect(rows.scheduled.map((job) => job.name)).toEqual([
      "summarize:summarizeMeeting",
      "summarize:summarizeMeeting",
    ]);
  });

  test("failed summary resync with unchanged contentHash reschedules summarize", async () => {
    vi.useFakeTimers();
    const t = authedTest();

    await t.mutation(upsertFromDevice, { payload: payload() });
    await t.run(async (ctx) => {
      const meeting = await ctx.db.query("meetings").unique();
      if (meeting === null) {
        throw new Error("missing meeting");
      }
      await ctx.db.patch(meeting._id, {
        summaryStatus: "failed",
        summaryError: "temporary outage",
      });
    });
    await t.mutation(upsertFromDevice, { payload: payload() });

    const rows = await allRows(t);
    expect(rows.scheduled).toHaveLength(2);
    expect(rows.scheduled.map((job) => job.name)).toEqual([
      "summarize:summarizeMeeting",
      "summarize:summarizeMeeting",
    ]);
    expect(rows.meetings[0].summaryStatus).toBe("pending");
    expect(rows.meetings[0].summaryError).toBeUndefined();
  });

  test("users only read their own meetings", async () => {
    vi.useFakeTimers();
    const backend = convexTest({ schema, modules });
    const userA = backend.withIdentity({
      issuer: "https://clerk.test",
      subject: "user-a",
      tokenIdentifier: "user-a",
    });
    const userB = backend.withIdentity({
      issuer: "https://clerk.test",
      subject: "user-b",
      tokenIdentifier: "user-b",
    });

    await userB.mutation(upsertFromDevice, {
      payload: payload({ localId: "shared-local-id" }),
    });

    await expect(
      userA.query(getByLocalId, { localId: "shared-local-id" }),
    ).resolves.toBeNull();
    await expect(
      userB.query(getByLocalId, { localId: "shared-local-id" }),
    ).resolves.toMatchObject({
      localId: "shared-local-id",
      userId: "user-b",
    });
  });

  test("readySummaries returns only the current user's ready summaries", async () => {
    vi.useFakeTimers();
    const backend = convexTest({ schema, modules });
    const userA = backend.withIdentity({
      issuer: "https://clerk.test",
      subject: "user-a",
      tokenIdentifier: "user-a",
    });
    const userB = backend.withIdentity({
      issuer: "https://clerk.test",
      subject: "user-b",
      tokenIdentifier: "user-b",
    });

    const first = await userA.mutation(upsertFromDevice, {
      payload: payload({ localId: "ready-a" }),
    });
    const second = await userA.mutation(upsertFromDevice, {
      payload: payload({ localId: "pending-a", contentHash: "hash-pending" }),
    });
    const third = await userB.mutation(upsertFromDevice, {
      payload: payload({ localId: "ready-b" }),
    });

    await backend.run(async (ctx) => {
      await ctx.db.patch(first.meetingId, {
        summary: "Ready for A",
        summaryStatus: "ready",
      });
      await ctx.db.patch(second.meetingId, {
        summary: "Pending for A",
        summaryStatus: "pending",
      });
      await ctx.db.patch(third.meetingId, {
        summary: "Ready for B",
        summaryStatus: "ready",
      });
    });

    await expect(userA.query(readySummaries, {})).resolves.toEqual([
      {
        localId: "ready-a",
        contentHash: "hash-1",
        summary: "Ready for A",
        summaryStatus: "ready",
      },
    ]);
  });

  test("summaryUpdates returns failed summaries for the current user", async () => {
    vi.useFakeTimers();
    const backend = convexTest({ schema, modules });
    const userA = backend.withIdentity({
      issuer: "https://clerk.test",
      subject: "user-a",
      tokenIdentifier: "user-a",
    });
    const userB = backend.withIdentity({
      issuer: "https://clerk.test",
      subject: "user-b",
      tokenIdentifier: "user-b",
    });

    const failed = await userA.mutation(upsertFromDevice, {
      payload: payload({ localId: "failed-a" }),
    });
    const other = await userB.mutation(upsertFromDevice, {
      payload: payload({ localId: "failed-b" }),
    });

    await backend.run(async (ctx) => {
      await ctx.db.patch(failed.meetingId, {
        summaryStatus: "failed",
        summaryError: "OpenRouter summary request failed: 502",
      });
      await ctx.db.patch(other.meetingId, {
        summaryStatus: "failed",
        summaryError: "Other user failure",
      });
    });

    await expect(userA.query(summaryUpdates, {})).resolves.toEqual([
      {
        localId: "failed-a",
        contentHash: "hash-1",
        summaryStatus: "failed",
        summaryError: "OpenRouter summary request failed: 502",
      },
    ]);
  });
});
