import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import { afterEach, describe, expect, test, vi } from "vitest";
import schema from "./schema";

const modules = import.meta.glob("./**/*.*s");

const upsertFromDevice =
  makeFunctionReference<"mutation">("meetings:upsertFromDevice");
const getByLocalId = makeFunctionReference<"query">("meetings:getByLocalId");

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
    participants: Array<{ name: string; email?: string }>;
    markdownBody: string;
    transcriptSegments: Segment[];
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
    expect(rows.notes).toHaveLength(1);
    expect(rows.notes[0].markdownBody).toBe("Updated meeting notes");
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
});
