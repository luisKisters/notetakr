import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import schema from "../schema";
import { CrmError, type CrmConfig } from "./provider";
import { attioProvider } from "./attio";

const modules = import.meta.glob("../**/*.*s");
const apiKey = process.env.ATTIO_TEST_API_KEY;
const hasLiveConfig = apiKey !== undefined && apiKey.trim() !== "";

if (!hasLiveConfig) {
  process.stderr.write(
    "WARNING: Skipping Attio live integration tests: ATTIO_TEST_API_KEY is required.\n",
  );
}

const liveDescribe = hasLiveConfig ? describe : describe.skip;
const cfg: CrmConfig = {
  provider: "attio",
  apiKey: apiKey ?? "missing",
};

function runId() {
  return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

async function liveRequest<T>(
  path: string,
  init: RequestInit = {},
  config: CrmConfig = cfg,
) {
  const response = await fetch(`https://api.attio.com/v2${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });

  if (!response.ok) {
    throw new Error(`Attio live request failed: ${response.status}`);
  }

  return (await response.json()) as T;
}

async function createLivePerson(email: string, fullName: string) {
  const [firstName, ...lastNameParts] = fullName.split(" ");
  const response = await liveRequest<{
    data: { id: { record_id: string } };
  }>("/objects/people/records", {
    method: "POST",
    body: JSON.stringify({
      data: {
        values: {
          email_addresses: [email],
          name: [
            {
              first_name: firstName,
              last_name: lastNameParts.join(" "),
              full_name: fullName,
            },
          ],
        },
      },
    }),
  });
  return response.data.id.record_id;
}

async function deleteLivePerson(personId: string | undefined) {
  if (personId === undefined) {
    return;
  }
  await liveRequest(`/objects/people/records/${encodeURIComponent(personId)}`, {
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

async function liveNotesForPerson(personId: string) {
  const response = await liveRequest<{
    data: Array<{
      id: { note_id: string };
      parent_object?: string;
      parent_record_id?: string;
      title?: string;
      content_markdown?: string;
      content_plaintext?: string;
    }>;
  }>(
    `/notes?${new URLSearchParams({
      parent_object: "people",
      parent_record_id: personId,
      limit: "50",
    }).toString()}`,
  );
  return response.data;
}

async function liveNote(noteId: string) {
  const response = await liveRequest<{
    data: {
      id: { note_id: string };
      title?: string;
      content_markdown?: string;
      content_plaintext?: string;
    };
  }>(`/notes/${encodeURIComponent(noteId)}`);
  return response.data;
}

async function mirrorPeopleIntoConvex(
  t: ReturnType<typeof convexTest>,
  userId: string,
  people?: Awaited<ReturnType<typeof attioProvider.listPeople>>,
) {
  const sourcePeople = people ?? (await attioProvider.listPeople(cfg));
  await t.run(async (ctx) => {
    for (const person of sourcePeople) {
      await ctx.db.insert("people", {
        userId,
        email: person.email,
        name: person.name,
        company: person.company,
        provider: "attio",
        remoteId: person.remoteId,
      });
    }
  });
}

liveDescribe("attio live integration", () => {
  test("live: listPeople returns a non-empty mapped page from the real instance", async () => {
    const people = await attioProvider.listPeople(cfg);

    expect(people.length).toBeGreaterThan(0);
    expect(people[0].remoteId).toEqual(expect.any(String));
    expect(people[0].name).toEqual(expect.any(String));
    expect(people[0].email).toBe(people[0].email.toLowerCase());
  });

  test("live: a person created via the API appears in the next mirror pass", async () => {
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
        provider: "attio",
        remoteId: personId,
      });
    } finally {
      await deleteLivePerson(personId);
    }
  });

  test("live: upsertMeetingNote creates exactly one note attached to the test person", async () => {
    const id = runId();
    const email = `nt-test+${id}@example.invalid`;
    let personId: string | undefined;
    let noteId: string | undefined;

    try {
      personId = await createLivePerson(email, `[nt-test] Note ${id}`);
      noteId = await attioProvider.upsertMeetingNote(
        cfg,
        [personId],
        `[nt-test] Meeting ${id}`,
        "## Summary\n\nLive note body.\n\n## Transcript\n\nHello.",
      );

      const notes = (await liveNotesForPerson(personId)).filter(
        (note) => note.id.note_id === noteId,
      );
      const note = await liveNote(noteId);
      expect(notes).toHaveLength(1);
      expect(note.title).toBe(`[nt-test] Meeting ${id}`);
      expect(note.content_markdown ?? note.content_plaintext).toContain(
        "Live note body.",
      );
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
    let updatedId: string | undefined;

    try {
      personId = await createLivePerson(email, `[nt-test] Update ${id}`);
      noteId = await attioProvider.upsertMeetingNote(
        cfg,
        [personId],
        `[nt-test] Meeting ${id}`,
        "first body",
      );
      updatedId = await attioProvider.upsertMeetingNote(
        cfg,
        [personId],
        `[nt-test] Meeting ${id}`,
        "second body",
        noteId,
      );

      expect(updatedId).not.toBe(noteId);
      const oldNotes = (await liveNotesForPerson(personId)).filter(
        (note) => note.id.note_id === noteId,
      );
      const newNotes = (await liveNotesForPerson(personId)).filter(
        (note) => note.id.note_id === updatedId,
      );
      const note = await liveNote(updatedId);
      expect(oldNotes).toHaveLength(0);
      expect(newNotes).toHaveLength(1);
      expect(note.content_markdown ?? note.content_plaintext).toContain(
        "second body",
      );
    } finally {
      await deleteLiveNote(updatedId);
      await deleteLiveNote(noteId);
      await deleteLivePerson(personId);
    }
  });

  test("live: invalid api key maps to typed CrmError.unauthorized", async () => {
    await expect(
      attioProvider.listPeople({
        ...cfg,
        apiKey: "notetakr-invalid-api-key",
      }),
    ).rejects.toMatchObject({
      name: "CrmError",
      code: "unauthorized",
    });
    await expect(
      attioProvider.listPeople({
        ...cfg,
        apiKey: "notetakr-invalid-api-key",
      }),
    ).rejects.toBeInstanceOf(CrmError);
  });
});
