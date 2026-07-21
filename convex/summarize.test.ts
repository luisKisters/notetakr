import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import { afterEach, describe, expect, test, vi } from "vitest";
import schema from "./schema";

const modules = import.meta.glob("./**/*.*s");

const upsertFromDevice =
  makeFunctionReference<"mutation">("meetings:upsertFromDevice");
const summarizeMeeting =
  makeFunctionReference<"action">("summarize:summarizeMeeting");

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
      { seq: 1, startMs: 1200, speaker: "Grace", text: "We need a demo." },
      { seq: 0, startMs: 0, speaker: "Ada", text: "Ship the sync spine." },
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

function openRouterSuccess(summary: string) {
  return vi.fn(async (_input: RequestInfo | URL, _init?: RequestInit) => {
    return new Response(
      JSON.stringify({
        choices: [{ message: { content: summary } }],
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  });
}

async function meetingById(t: ReturnType<typeof authedTest>, meetingId: string) {
  return await t.run(async (ctx) => {
    return await ctx.db.get(meetingId as never);
  });
}

async function scheduledFunctions(t: ReturnType<typeof authedTest>) {
  return await t.run(async (ctx) => {
    return await ctx.db.system.query("_scheduled_functions").collect();
  });
}

afterEach(() => {
  delete process.env.OPENROUTER_API_KEY;
  delete process.env.SUMMARY_MODEL;
  vi.unstubAllGlobals();
  vi.clearAllTimers();
  vi.useRealTimers();
});

describe("summarize", () => {
  test("writes summary and status ready on success", async () => {
    vi.useFakeTimers();
    process.env.OPENROUTER_API_KEY = "test-openrouter-key";
    const fetchMock = openRouterSuccess("Summary: ship the sync spine.");
    vi.stubGlobal("fetch", fetchMock);
    const t = authedTest();

    const { meetingId } = await t.mutation(upsertFromDevice, {
      payload: payload(),
    });

    await expect(t.action(summarizeMeeting, { meetingId })).resolves.toEqual({
      status: "ready",
      summary: "Summary: ship the sync spine.",
    });

    const meeting = await meetingById(t, meetingId);
    expect(meeting).toMatchObject({
      summary: "Summary: ship the sync spine.",
      summaryStatus: "ready",
    });
    expect(fetchMock).toHaveBeenCalledOnce();
    const [, init] = fetchMock.mock.calls[0];
    const headers = init?.headers as Record<string, string>;
    const body = JSON.parse(init?.body as string);
    expect(headers.Authorization).toBe("Bearer test-openrouter-key");
    expect(body.model).toBe("moonshotai/kimi-k2.7-code");
    expect(body.messages.at(-1).content).toContain("Ada: Ship the sync spine.");
    expect(body.messages.at(-1).content).toContain("Grace: We need a demo.");
  });

  test("sets status failed and preserves previous summary on API error", async () => {
    vi.useFakeTimers();
    process.env.OPENROUTER_API_KEY = "test-openrouter-key";
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("bad gateway", { status: 502 })),
    );
    const t = authedTest();

    const { meetingId } = await t.mutation(upsertFromDevice, {
      payload: payload(),
    });
    await t.run(async (ctx) => {
      await ctx.db.patch(meetingId, {
        summary: "Previous summary",
        summaryStatus: "ready",
      });
    });

    await expect(t.action(summarizeMeeting, { meetingId })).resolves.toEqual({
      status: "failed",
    });

    const meeting = await meetingById(t, meetingId);
    expect(meeting).toMatchObject({
      summary: "Previous summary",
      summaryStatus: "failed",
      summaryError: "OpenRouter summary request failed: 502",
    });
  });

  test("stale summary response does not overwrite changed content", async () => {
    vi.useFakeTimers();
    process.env.OPENROUTER_API_KEY = "test-openrouter-key";
    let releaseFetch: ((response: Response) => void) | undefined;
    const fetchStarted = new Promise<void>((resolve) => {
      vi.stubGlobal(
        "fetch",
        vi.fn(
          async () =>
            await new Promise<Response>((release) => {
              releaseFetch = release;
              resolve();
            }),
        ),
      );
    });
    const t = authedTest();

    const { meetingId } = await t.mutation(upsertFromDevice, {
      payload: payload({ contentHash: "hash-old" }),
    });

    const actionResult = t.action(summarizeMeeting, { meetingId });
    await fetchStarted;
    await t.mutation(upsertFromDevice, {
      payload: payload({
        contentHash: "hash-new",
        markdownBody: "Newer content",
      }),
    });
    releaseFetch?.(
      new Response(
        JSON.stringify({
          choices: [{ message: { content: "Stale summary" } }],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );

    await expect(actionResult).resolves.toEqual({ status: "stale" });
    await expect(meetingById(t, meetingId)).resolves.toMatchObject({
      contentHash: "hash-new",
      summaryStatus: "pending",
    });
    const meeting = await meetingById(t, meetingId);
    expect((meeting as { summary?: string } | null)?.summary).toBeUndefined();
  });

  test("schedules crm push after ready", async () => {
    vi.useFakeTimers();
    process.env.OPENROUTER_API_KEY = "test-openrouter-key";
    vi.stubGlobal("fetch", openRouterSuccess("Ready for CRM."));
    const t = authedTest();

    const { meetingId } = await t.mutation(upsertFromDevice, {
      payload: payload(),
    });

    await t.action(summarizeMeeting, { meetingId });

    const scheduled = await scheduledFunctions(t);
    const crmPushes = scheduled.filter(
      (job) => job.name === "crm/push:pushMeetingToCrm",
    );
    expect(crmPushes).toHaveLength(1);
    expect(crmPushes[0].args[0]).toEqual({ meetingId });
  });
});
