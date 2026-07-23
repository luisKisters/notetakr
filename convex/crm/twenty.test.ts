import { afterEach, describe, expect, test, vi } from "vitest";
import { CrmError, getCrmProvider } from "./provider";
import { twentyProvider } from "./twenty";
import { setSafeCrmFetchForTesting } from "./safeFetch";

const cfg = {
  provider: "twenty",
  baseUrl: "https://twenty.test",
  apiKey: "test-api-key",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function fetchMock(...responses: Response[]) {
  const fetch = vi.fn(
    async (
      _input: RequestInfo | URL,
      _init?: RequestInit,
    ): Promise<Response> => {
      const response = responses.shift();
      if (response === undefined) {
        throw new Error("No mocked response left");
      }
      return response;
    },
  );
  setSafeCrmFetchForTesting(fetch);
  return fetch;
}

afterEach(() => {
  setSafeCrmFetchForTesting(undefined);
  vi.unstubAllGlobals();
});

describe("twenty provider", () => {
  test("listPeople maps twenty records to CrmPerson with lowercased emails", async () => {
    vi.stubGlobal(
      "fetch",
      fetchMock(
        jsonResponse({
          data: {
            people: [
              {
                id: "person-1",
                name: { firstName: "Ada", lastName: "Lovelace" },
                emails: {
                  primaryEmail: "ADA@Example.COM",
                  additionalEmails: ["Analyst@Example.COM"],
                },
                company: { name: "Analytical Engines" },
              },
              {
                id: "person-2",
                name: { firstName: "Grace", lastName: "Hopper" },
                emails: {
                  primaryEmail: "",
                  additionalEmails: ["GRACE@Example.COM"],
                },
              },
            ],
          },
          pageInfo: { hasNextPage: false },
        }),
      ),
    );

    await expect(twentyProvider.listPeople(cfg)).resolves.toEqual([
      {
        remoteId: "person-1",
        name: "Ada Lovelace",
        email: "ada@example.com",
        company: "Analytical Engines",
      },
      {
        remoteId: "person-1",
        name: "Ada Lovelace",
        email: "analyst@example.com",
        company: "Analytical Engines",
      },
      {
        remoteId: "person-2",
        name: "Grace Hopper",
        email: "grace@example.com",
      },
    ]);
  });

  test("listPeople follows pagination until exhausted", async () => {
    const fetch = fetchMock(
      jsonResponse({
        data: {
          people: [
            {
              id: "person-1",
              name: { firstName: "Ada", lastName: "Lovelace" },
              emails: { primaryEmail: "ada@example.com" },
            },
          ],
        },
        pageInfo: { hasNextPage: true, endCursor: "cursor-1" },
      }),
      jsonResponse({
        data: {
          people: [
            {
              id: "person-2",
              name: { firstName: "Grace", lastName: "Hopper" },
              emails: { primaryEmail: "grace@example.com" },
            },
          ],
        },
        pageInfo: { hasNextPage: false, endCursor: "cursor-2" },
      }),
    );
    vi.stubGlobal("fetch", fetch);

    await expect(twentyProvider.listPeople(cfg)).resolves.toHaveLength(2);

    expect(fetch).toHaveBeenCalledTimes(2);
    const firstUrl = new URL(fetch.mock.calls[0][0] as string);
    const secondUrl = new URL(fetch.mock.calls[1][0] as string);
    expect(firstUrl.pathname).toBe("/rest/people");
    expect(firstUrl.searchParams.get("limit")).toBe("60");
    expect(firstUrl.searchParams.has("starting_after")).toBe(false);
    expect(secondUrl.searchParams.get("starting_after")).toBe("cursor-1");
  });

  test("upsertMeetingNote creates note and attaches all person targets", async () => {
    const fetch = fetchMock(
      jsonResponse({
        data: { createNote: { id: "note-1" } },
      }, 201),
      jsonResponse({ data: { createNoteTarget: { id: "target-1" } } }, 201),
      jsonResponse({ data: { createNoteTarget: { id: "target-2" } } }, 201),
    );
    vi.stubGlobal("fetch", fetch);

    await expect(
      twentyProvider.upsertMeetingNote(
        cfg,
        ["person-1", "person-2"],
        "Weekly Review",
        "## Summary\nShip it.",
      ),
    ).resolves.toBe("note-1");

    expect(fetch).toHaveBeenCalledTimes(3);
    const [noteUrl, noteInit] = fetch.mock.calls[0];
    expect(noteUrl).toBe("https://twenty.test/rest/notes");
    expect(noteInit?.method).toBe("POST");
    expect(JSON.parse(noteInit?.body as string)).toEqual({
      title: "Weekly Review",
      bodyV2: { markdown: "## Summary\nShip it." },
    });
    const targetBodies = fetch.mock.calls
      .slice(1)
      .map(([, init]) => JSON.parse(init?.body as string));
    expect(targetBodies).toEqual([
      { noteId: "note-1", targetPersonId: "person-1" },
      { noteId: "note-1", targetPersonId: "person-2" },
    ]);
  });

  test("upsertMeetingNote with existingNoteId updates instead of creating", async () => {
    const fetch = fetchMock(
      jsonResponse({
        data: { updateNote: { id: "note-1" } },
      }),
      jsonResponse({
        data: {
          noteTargets: [
            {
              id: "target-1",
              noteId: "note-1",
              targetPersonId: "person-1",
            },
          ],
        },
        pageInfo: { hasNextPage: false },
      }),
    );
    vi.stubGlobal("fetch", fetch);

    await expect(
      twentyProvider.upsertMeetingNote(
        cfg,
        ["person-1"],
        "Weekly Review",
        "Updated markdown",
        "note-1",
      ),
    ).resolves.toBe("note-1");

    expect(fetch).toHaveBeenCalledTimes(2);
    const [url, init] = fetch.mock.calls[0];
    expect(url).toBe("https://twenty.test/rest/notes/note-1");
    expect(init?.method).toBe("PATCH");
    expect(JSON.parse(init?.body as string)).toEqual({
      title: "Weekly Review",
      bodyV2: { markdown: "Updated markdown" },
    });
    const [targetsUrl, targetsInit] = fetch.mock.calls[1];
    expect(targetsUrl).toBe(
      "https://twenty.test/rest/noteTargets?limit=60&depth=1",
    );
    expect(targetsInit?.method).toBe("GET");
  });

  test("upsertMeetingNote with existingNoteId attaches newly matched targets", async () => {
    const fetch = fetchMock(
      jsonResponse({
        data: { updateNote: { id: "note-1" } },
      }),
      jsonResponse({
        data: {
          noteTargets: [
            {
              id: "target-1",
              noteId: "note-1",
              targetPersonId: "person-1",
            },
          ],
        },
        pageInfo: { hasNextPage: false },
      }),
      jsonResponse({ data: { createNoteTarget: { id: "target-2" } } }, 201),
    );
    vi.stubGlobal("fetch", fetch);

    await expect(
      twentyProvider.upsertMeetingNote(
        cfg,
        ["person-1", "person-2"],
        "Weekly Review",
        "Updated markdown",
        "note-1",
      ),
    ).resolves.toBe("note-1");

    expect(fetch).toHaveBeenCalledTimes(3);
    const [targetUrl, targetInit] = fetch.mock.calls[2];
    expect(targetUrl).toBe("https://twenty.test/rest/noteTargets");
    expect(targetInit?.method).toBe("POST");
    expect(JSON.parse(targetInit?.body as string)).toEqual({
      noteId: "note-1",
      targetPersonId: "person-2",
    });
  });

  test("upsertMeetingNote with existingNoteId removes stale targets", async () => {
    const fetch = fetchMock(
      jsonResponse({
        data: { updateNote: { id: "note-1" } },
      }),
      jsonResponse({
        data: {
          noteTargets: [
            {
              id: "target-1",
              noteId: "note-1",
              targetPersonId: "person-1",
            },
            {
              id: "target-2",
              noteId: "note-1",
              targetPersonId: "person-2",
            },
          ],
        },
        pageInfo: { hasNextPage: false },
      }),
      new Response(null, { status: 204 }),
    );
    vi.stubGlobal("fetch", fetch);

    await expect(
      twentyProvider.upsertMeetingNote(
        cfg,
        ["person-1"],
        "Weekly Review",
        "Updated markdown",
        "note-1",
      ),
    ).resolves.toBe("note-1");

    expect(fetch).toHaveBeenCalledTimes(3);
    const [deleteUrl, deleteInit] = fetch.mock.calls[2];
    expect(deleteUrl).toBe("https://twenty.test/rest/noteTargets/target-2");
    expect(deleteInit?.method).toBe("DELETE");
  });

  test("upsertMeetingNote with stale existingNoteId creates a fresh note", async () => {
    const fetch = fetchMock(
      jsonResponse({ errors: [{ message: "Not found" }] }, 404),
      jsonResponse({
        data: { createNote: { id: "note-replacement" } },
      }, 201),
      jsonResponse({ data: { createNoteTarget: { id: "target-1" } } }, 201),
    );
    vi.stubGlobal("fetch", fetch);

    await expect(
      twentyProvider.upsertMeetingNote(
        cfg,
        ["person-1"],
        "Weekly Review",
        "Updated markdown",
        "stale-note-id",
      ),
    ).resolves.toBe("note-replacement");

    expect(fetch).toHaveBeenCalledTimes(3);
    const [patchUrl, patchInit] = fetch.mock.calls[0];
    const [createUrl, createInit] = fetch.mock.calls[1];
    const [targetUrl, targetInit] = fetch.mock.calls[2];
    expect(patchUrl).toBe("https://twenty.test/rest/notes/stale-note-id");
    expect(patchInit?.method).toBe("PATCH");
    expect(createUrl).toBe("https://twenty.test/rest/notes");
    expect(createInit?.method).toBe("POST");
    expect(targetUrl).toBe("https://twenty.test/rest/noteTargets");
    expect(targetInit?.method).toBe("POST");
    expect(JSON.parse(targetInit?.body as string)).toEqual({
      noteId: "note-replacement",
      targetPersonId: "person-1",
    });
  });

  test("api error surfaces as typed CrmError, not a throw-through", async () => {
    vi.stubGlobal(
      "fetch",
      fetchMock(jsonResponse({ errors: [{ message: "Unauthorized" }] }, 401)),
    );

    let error: unknown;
    try {
      await twentyProvider.listPeople(cfg);
    } catch (caught) {
      error = caught;
    }
    expect(error).toMatchObject({
      name: "CrmError",
      code: "unauthorized",
      status: 401,
    });
    expect(error).not.toBeInstanceOf(TypeError);
    expect(getCrmProvider("twenty")).toBe(twentyProvider);
    expect(CrmError.unauthorized(401)).toBeInstanceOf(CrmError);
  });
});
