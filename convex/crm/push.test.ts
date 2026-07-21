import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import { describe, expect, test, vi } from "vitest";
import schema from "../schema";
import { registerCrmProvider } from "./provider";

const modules = {
  ...import.meta.glob("../*.ts"),
  ...import.meta.glob("../_generated/*.*s"),
  ...Object.fromEntries(
    Object.entries(import.meta.glob("./*.ts")).map(([path, loader]) => [
      `../crm/${path.slice(2)}`,
      loader,
    ]),
  ),
};

const pushMeetingToCrm =
  makeFunctionReference<"action">("crm/push:pushMeetingToCrm");

type Participant = {
  name: string;
  email?: string;
  crm?: string;
};

type PushCall = {
  personRemoteIds: string[];
  title: string;
  markdown: string;
  existingNoteId?: string;
};

function backend() {
  return convexTest({ schema, modules });
}

function registerPushProvider(noteId = "note-1") {
  const calls: PushCall[] = [];
  const listPeople = vi.fn(async () => []);
  const upsertMeetingNote = vi.fn(
    async (
      _cfg,
      personRemoteIds: string[],
      title: string,
      markdown: string,
      existingNoteId?: string,
    ) => {
      calls.push({ personRemoteIds, title, markdown, existingNoteId });
      return noteId;
    },
  );
  registerCrmProvider({
    providerId: "push-test",
    listPeople,
    upsertMeetingNote,
  });
  return { calls, listPeople, upsertMeetingNote };
}

async function seedMeeting(
  t: ReturnType<typeof backend>,
  overrides: Partial<{
    userId: string;
    participants: Participant[];
    summary: string;
    crmNoteId: string;
    pushStatus: "pending" | "pushed" | "failed" | "skipped";
    crmPushOptOut: boolean;
    configureCrm: boolean;
    people: Array<{ email: string; remoteId: string; name?: string }>;
  }> = {},
) {
  const userId = overrides.userId ?? "user-a";
  return await t.run(async (ctx) => {
    if (overrides.configureCrm !== false) {
      await ctx.db.insert("userSettings", {
        userId,
        crm: {
          provider: "push-test",
          baseUrl: "https://crm.test",
          encryptedApiKey: "test-key",
        },
      });
    }

    const meetingId = await ctx.db.insert("meetings", {
      userId,
      localId: "meeting-1",
      title: "Weekly Review",
      startedAt: "2026-07-20T16:00:00Z",
      participants: overrides.participants ?? [
        { name: "Ada Lovelace", email: "ada@example.com" },
      ],
      contentHash: "hash-1",
      summary: overrides.summary ?? "Ship the sync spine.",
      summaryStatus: "ready",
      crmNoteId: overrides.crmNoteId,
      pushStatus: overrides.pushStatus,
      crmPushOptOut: overrides.crmPushOptOut,
    });

    await ctx.db.insert("notes", {
      userId,
      meetingId,
      markdownBody: "Local note body",
    });
    await ctx.db.insert("transcriptSegments", {
      userId,
      meetingId,
      seq: 1,
      startMs: 1000,
      speaker: "Grace",
      text: "We need the CRM note.",
    });
    await ctx.db.insert("transcriptSegments", {
      userId,
      meetingId,
      seq: 0,
      startMs: 0,
      speaker: "Ada",
      text: "The summary is ready.",
    });

    for (const person of overrides.people ?? [
      { email: "ada@example.com", remoteId: "person-1", name: "Ada Lovelace" },
    ]) {
      await ctx.db.insert("people", {
        userId,
        email: person.email,
        name: person.name ?? person.email,
        provider: "push-test",
        remoteId: person.remoteId,
      });
    }

    return meetingId;
  });
}

async function meetingById(t: ReturnType<typeof backend>, meetingId: string) {
  return await t.run(async (ctx) => {
    return await ctx.db.get(meetingId as never);
  });
}

describe("crm push", () => {
  test("matches participants to people by case-insensitive email", async () => {
    const provider = registerPushProvider();
    const t = backend();
    const meetingId = await seedMeeting(t, {
      participants: [{ name: "Ada Lovelace", email: "ADA@Example.COM" }],
      people: [
        { email: "ada@example.com", remoteId: "person-1", name: "Ada" },
      ],
    });

    await t.action(pushMeetingToCrm, { meetingId });

    expect(provider.calls).toHaveLength(1);
    expect(provider.calls[0].personRemoteIds).toEqual(["person-1"]);
  });

  test("matches participants by explicit crm remote id before email", async () => {
    const provider = registerPushProvider();
    const t = backend();
    const meetingId = await seedMeeting(t, {
      participants: [
        { name: "Manually Matched", crm: "person-2" },
        { name: "Email Changed", email: "old@example.com", crm: "person-3" },
      ],
      people: [
        { email: "current@example.com", remoteId: "person-2", name: "Manual" },
        { email: "new@example.com", remoteId: "person-3", name: "Changed" },
      ],
    });

    await t.action(pushMeetingToCrm, { meetingId });

    expect(provider.calls).toHaveLength(1);
    expect(provider.calls[0].personRemoteIds).toEqual(["person-2", "person-3"]);
    await expect(meetingById(t, meetingId)).resolves.toMatchObject({
      unmatchedParticipants: [],
      pushStatus: "pushed",
    });
  });

  test("unmatched participants are recorded and do not block the push", async () => {
    const provider = registerPushProvider();
    const t = backend();
    const meetingId = await seedMeeting(t, {
      participants: [
        { name: "Ada Lovelace", email: "ada@example.com" },
        { name: "No Email" },
        { name: "External Guest", email: "guest@example.com" },
      ],
    });

    await t.action(pushMeetingToCrm, { meetingId });

    expect(provider.calls).toHaveLength(1);
    expect(provider.calls[0].personRemoteIds).toEqual(["person-1"]);
    await expect(meetingById(t, meetingId)).resolves.toMatchObject({
      unmatchedParticipants: [
        { name: "No Email" },
        { name: "External Guest", email: "guest@example.com" },
      ],
      pushStatus: "pushed",
    });
  });

  test("stores crmNoteId and sets pushStatus pushed", async () => {
    const provider = registerPushProvider("note-created");
    const t = backend();
    const meetingId = await seedMeeting(t);

    await t.action(pushMeetingToCrm, { meetingId });

    expect(provider.calls).toHaveLength(1);
    expect(provider.calls[0].title).toBe("Weekly Review");
    expect(provider.calls[0].markdown).toContain("## Summary");
    expect(provider.calls[0].markdown).toContain("Ship the sync spine.");
    expect(provider.calls[0].markdown).toContain("## Transcript");
    expect(provider.calls[0].markdown).toContain(
      "Ada: The summary is ready.",
    );
    await expect(meetingById(t, meetingId)).resolves.toMatchObject({
      crmNoteId: "note-created",
      pushStatus: "pushed",
    });
  });

  test("retry after transient failure reuses crmNoteId (no duplicate note)", async () => {
    const provider = registerPushProvider("note-existing");
    const t = backend();
    const meetingId = await seedMeeting(t, {
      crmNoteId: "note-existing",
      pushStatus: "failed",
    });

    await t.action(pushMeetingToCrm, { meetingId });

    expect(provider.calls).toHaveLength(1);
    expect(provider.calls[0].existingNoteId).toBe("note-existing");
    await expect(meetingById(t, meetingId)).resolves.toMatchObject({
      crmNoteId: "note-existing",
      pushStatus: "pushed",
    });
  });

  test("crmPushOptOut yields pushStatus skipped and zero provider calls", async () => {
    const provider = registerPushProvider();
    const t = backend();
    const meetingId = await seedMeeting(t, {
      crmPushOptOut: true,
    });

    await t.action(pushMeetingToCrm, { meetingId });

    expect(provider.upsertMeetingNote).not.toHaveBeenCalled();
    await expect(meetingById(t, meetingId)).resolves.toMatchObject({
      pushStatus: "skipped",
    });
  });

  test("no crm configured yields zero provider calls", async () => {
    const provider = registerPushProvider();
    const t = backend();
    const meetingId = await seedMeeting(t, {
      configureCrm: false,
    });

    await t.action(pushMeetingToCrm, { meetingId });

    expect(provider.upsertMeetingNote).not.toHaveBeenCalled();
    await expect(meetingById(t, meetingId)).resolves.toMatchObject({
      pushStatus: "skipped",
    });
  });
});
