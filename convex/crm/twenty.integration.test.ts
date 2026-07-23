import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import schema from "../schema";
import { CrmError, type CrmConfig } from "./provider";
import { twentyProvider } from "./twenty";

const modules = import.meta.glob("../**/*.*s");
const baseUrl = process.env.TWENTY_TEST_BASE_URL;
const apiKey = process.env.TWENTY_TEST_API_KEY;
const hasLiveConfig =
  baseUrl !== undefined &&
  baseUrl.trim() !== "" &&
  apiKey !== undefined &&
  apiKey.trim() !== "";

if (!hasLiveConfig) {
  process.stderr.write(
    "WARNING: Skipping Twenty live integration tests: TWENTY_TEST_BASE_URL and TWENTY_TEST_API_KEY are required.\n",
  );
}

const liveDescribe = hasLiveConfig ? describe : describe.skip;
const cfg: CrmConfig = {
  provider: "twenty",
  baseUrl: baseUrl ?? "https://twenty.invalid",
  apiKey: apiKey ?? "missing",
};

function runId() {
  return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function restBase(config: CrmConfig) {
  const trimmed = config.baseUrl?.replace(/\/+$/, "");
  if (trimmed === undefined || trimmed === "") {
    throw new Error("TWENTY_TEST_BASE_URL is not configured");
  }
  return trimmed.endsWith("/rest") ? trimmed : `${trimmed}/rest`;
}

async function liveRequest<T>(
  path: string,
  init: RequestInit = {},
  config: CrmConfig = cfg,
) {
  const response = await fetch(`${restBase(config)}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });

  if (!response.ok) {
    throw new Error(`Twenty live request failed: ${response.status}`);
  }

  return (await response.json()) as T;
}

async function createLivePerson(email: string, firstName: string) {
  const response = await liveRequest<{
    data: { createPerson: { id: string } };
  }>("/people", {
    method: "POST",
    body: JSON.stringify({
      name: { firstName, lastName: "Probe" },
      emails: { primaryEmail: email, additionalEmails: [] },
    }),
  });
  return response.data.createPerson.id;
}

async function deleteLivePerson(personId: string | undefined) {
  if (personId === undefined) {
    return;
  }
  await liveRequest(`/people/${encodeURIComponent(personId)}`, {
    method: "DELETE",
  }).catch(() => undefined);
}

async function deleteLiveNote(noteId: string | undefined) {
  if (noteId === undefined) {
    return;
  }
  await liveRequest(`/notes/${encodeURIComponent(noteId)}`, {
    method: "DELETE",
  }).catch(() => undefined);
}

async function noteTargetsForPerson(personId: string) {
  const targets: Array<{ noteId?: string; targetPersonId?: string }> = [];
  let startingAfter: string | undefined;

  while (true) {
    const query = new URLSearchParams({ limit: "60", depth: "1" });
    if (startingAfter !== undefined) {
      query.set("starting_after", startingAfter);
    }
    const response = await liveRequest<{
      data: {
        noteTargets: Array<{ noteId?: string; targetPersonId?: string }>;
      };
      pageInfo?: { hasNextPage?: boolean; endCursor?: string };
    }>(`/noteTargets?${query.toString()}`);

    targets.push(
      ...response.data.noteTargets.filter(
        (target) => target.targetPersonId === personId,
      ),
    );

    if (
      response.pageInfo?.hasNextPage !== true ||
      response.pageInfo.endCursor === undefined
    ) {
      break;
    }
    startingAfter = response.pageInfo.endCursor;
  }

  return targets;
}

async function liveNote(noteId: string) {
  const response = await liveRequest<{
    data: {
      note: {
        id: string;
        title?: string;
        body?: string;
        bodyV2?: { markdown?: string };
      };
    };
  }>(`/notes/${encodeURIComponent(noteId)}`);
  return response.data.note;
}

async function mirrorPeopleIntoConvex(
  t: ReturnType<typeof convexTest>,
  userId: string,
  people?: Awaited<ReturnType<typeof twentyProvider.listPeople>>,
) {
  const sourcePeople = people ?? (await twentyProvider.listPeople(cfg));
  await t.run(async (ctx) => {
    for (const person of sourcePeople) {
      await ctx.db.insert("people", {
        userId,
        email: person.email,
        name: person.name,
        company: person.company,
        provider: "twenty",
        remoteId: person.remoteId,
      });
    }
  });
}

liveDescribe("twenty live integration", () => {
  test(
    "live: listPeople returns a non-empty mapped page from the real instance",
    { timeout: 30_000 },
    async () => {
      const people = await twentyProvider.listPeople(cfg);

      expect(people.length).toBeGreaterThan(0);
      expect(people[0].remoteId).toEqual(expect.any(String));
      expect(people[0].name).toEqual(expect.any(String));
      expect(people[0].email).toBe(people[0].email.toLowerCase());
    },
  );

  test(
    "live: a person created via the API appears in the next mirror pass",
    { timeout: 30_000 },
    async () => {
      const id = runId();
      const email = `nt-test+${id}@example.invalid`;
      let personId: string | undefined;

      try {
        personId = await createLivePerson(email, `[nt-test] Mirror ${id}`);
        const backend = convexTest({ schema, modules });

        await mirrorPeopleIntoConvex(backend, "user-a");

        const mirrored = await backend.run(async (ctx) => {
          return await ctx.db
            .query("people")
            .withIndex("by_user_email", (q) =>
              q.eq("userId", "user-a").eq("email", email),
            )
            .unique();
        });
        expect(mirrored).toMatchObject({
          email,
          name: expect.stringContaining("[nt-test]"),
          provider: "twenty",
          remoteId: personId,
        });
      } finally {
        await deleteLivePerson(personId);
      }
    },
  );

  test("live: upsertMeetingNote creates exactly one note attached to the test person", async () => {
    const id = runId();
    const email = `nt-test+${id}@example.invalid`;
    let personId: string | undefined;
    let noteId: string | undefined;

    try {
      personId = await createLivePerson(email, `[nt-test] Note ${id}`);
      noteId = await twentyProvider.upsertMeetingNote(
        cfg,
        [personId],
        `[nt-test] Meeting ${id}`,
        "## Summary\n\nLive note body.\n\n## Transcript\n\nHello.",
      );

      const targets = (await noteTargetsForPerson(personId)).filter(
        (target) => target.noteId === noteId,
      );
      const note = await liveNote(noteId);
      expect(targets).toHaveLength(1);
      expect(note.title).toBe(`[nt-test] Meeting ${id}`);
      expect(note.bodyV2?.markdown ?? note.body).toContain("Live note body.");
    } finally {
      await deleteLiveNote(noteId);
      await deleteLivePerson(personId);
    }
  });

  test("live: second upsert with the returned crmNoteId updates in place", async () => {
    const id = runId();
    const email = `nt-test+${id}@example.invalid`;
    let personId: string | undefined;
    let noteId: string | undefined;

    try {
      personId = await createLivePerson(email, `[nt-test] Update ${id}`);
      noteId = await twentyProvider.upsertMeetingNote(
        cfg,
        [personId],
        `[nt-test] Meeting ${id}`,
        "first body",
      );
      const updatedId = await twentyProvider.upsertMeetingNote(
        cfg,
        [personId],
        `[nt-test] Meeting ${id}`,
        "second body",
        noteId,
      );

      expect(updatedId).toBe(noteId);
      const targets = (await noteTargetsForPerson(personId)).filter(
        (target) => target.noteId === noteId,
      );
      const note = await liveNote(noteId);
      expect(targets).toHaveLength(1);
      expect(note.bodyV2?.markdown ?? note.body).toContain("second body");
    } finally {
      await deleteLiveNote(noteId);
      await deleteLivePerson(personId);
    }
  });

  test("live: invalid api key maps to typed CrmError.unauthorized", async () => {
    await expect(
      twentyProvider.listPeople({
        ...cfg,
        apiKey: "notetakr-invalid-api-key",
      }),
    ).rejects.toMatchObject({
      name: "CrmError",
      code: "unauthorized",
    });
    await expect(
      twentyProvider.listPeople({
        ...cfg,
        apiKey: "notetakr-invalid-api-key",
      }),
    ).rejects.toBeInstanceOf(CrmError);
  });
});
