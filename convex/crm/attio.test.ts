import { afterEach, describe, expect, test, vi } from "vitest";
import { CrmError, getCrmProvider, requireCrmProvider } from "./provider";
import { attioProvider } from "./attio";
import { setSafeCrmFetchForTesting } from "./safeFetch";

const cfg = {
  provider: "attio",
  baseUrl: "https://attio.test",
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

function attioPerson(
  recordId: string,
  name: string | undefined,
  emails: string[],
) {
  return {
    id: {
      workspace_id: "workspace-1",
      object_id: "people-object",
      record_id: recordId,
    },
    values: {
      ...(name === undefined
        ? {}
        : {
            name: [
              {
                full_name: name,
                first_name: name.split(" ")[0],
                last_name: name.split(" ").slice(1).join(" "),
                attribute_type: "personal-name",
              },
            ],
          }),
      email_addresses: emails.map((email) => ({
        original_email_address: email,
        email_address: email,
        attribute_type: "email-address",
      })),
    },
  };
}

function fullPage(prefix: string) {
  return Array.from({ length: 500 }, (_, index) =>
    attioPerson(
      `${prefix}-${index}`,
      `Person ${index}`,
      [`${prefix}-${index}@example.com`],
    ),
  );
}

afterEach(() => {
  setSafeCrmFetchForTesting(undefined);
  vi.unstubAllGlobals();
});

describe("attio provider", () => {
  test("listPeople maps attio records to CrmPerson with lowercased emails", async () => {
    vi.stubGlobal(
      "fetch",
      fetchMock(
        jsonResponse({
          data: [
            attioPerson("person-1", "Ada Lovelace", [
              "ADA@Example.COM",
              "Analyst@Example.COM",
            ]),
            attioPerson("person-2", "Grace Hopper", [
              "",
              "GRACE@Example.COM",
            ]),
          ],
        }),
      ),
    );

    await expect(attioProvider.listPeople(cfg)).resolves.toEqual([
      {
        remoteId: "person-1",
        name: "Ada Lovelace",
        email: "ada@example.com",
      },
      {
        remoteId: "person-1",
        name: "Ada Lovelace",
        email: "analyst@example.com",
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
      jsonResponse({ data: fullPage("page-1") }),
      jsonResponse({
        data: [attioPerson("person-last", "Last Person", ["last@example.com"])],
      }),
    );
    vi.stubGlobal("fetch", fetch);

    await expect(attioProvider.listPeople(cfg)).resolves.toHaveLength(501);

    expect(fetch).toHaveBeenCalledTimes(2);
    const [firstUrl, firstInit] = fetch.mock.calls[0];
    const [secondUrl, secondInit] = fetch.mock.calls[1];
    expect(firstUrl).toBe(
      "https://attio.test/v2/objects/people/records/query",
    );
    expect(secondUrl).toBe(
      "https://attio.test/v2/objects/people/records/query",
    );
    expect(JSON.parse(firstInit?.body as string)).toMatchObject({
      limit: 500,
      offset: 0,
    });
    expect(JSON.parse(secondInit?.body as string)).toMatchObject({
      limit: 500,
      offset: 500,
    });
  });

  test("upsertMeetingNote creates note and attaches all person targets", async () => {
    const fetch = fetchMock(
      jsonResponse({ data: { id: { note_id: "note-1" } } }),
      jsonResponse({ data: { id: { note_id: "note-2" } } }),
    );
    vi.stubGlobal("fetch", fetch);

    const remoteNoteId = await attioProvider.upsertMeetingNote(
      cfg,
      ["person-1", "person-2"],
      "Weekly Review",
      "## Summary\nShip it.",
    );

    expect(JSON.parse(remoteNoteId)).toEqual({
      provider: "attio",
      notes: [
        { personRemoteId: "person-1", noteId: "note-1" },
        { personRemoteId: "person-2", noteId: "note-2" },
      ],
    });
    expect(fetch).toHaveBeenCalledTimes(2);
    const noteBodies = fetch.mock.calls.map(([, init]) =>
      JSON.parse(init?.body as string),
    );
    expect(noteBodies).toEqual([
      {
        data: {
          parent_object: "people",
          parent_record_id: "person-1",
          title: "Weekly Review",
          format: "markdown",
          content: "## Summary\nShip it.",
        },
      },
      {
        data: {
          parent_object: "people",
          parent_record_id: "person-2",
          title: "Weekly Review",
          format: "markdown",
          content: "## Summary\nShip it.",
        },
      },
    ]);
  });

  test("upsertMeetingNote with existingNoteId updates instead of creating", async () => {
    const fetch = fetchMock(
      jsonResponse({ data: { id: { note_id: "note-replacement" } } }),
      jsonResponse({ data: null }),
    );
    vi.stubGlobal("fetch", fetch);

    await expect(
      attioProvider.upsertMeetingNote(
        cfg,
        ["person-1"],
        "Weekly Review",
        "Updated markdown",
        "note-existing",
      ),
    ).resolves.toBe("note-replacement");

    expect(fetch).toHaveBeenCalledTimes(2);
    const [createUrl, createInit] = fetch.mock.calls[0];
    const [deleteUrl, deleteInit] = fetch.mock.calls[1];
    expect(deleteUrl).toBe("https://attio.test/v2/notes/note-existing");
    expect(deleteInit?.method).toBe("DELETE");
    expect(createUrl).toBe("https://attio.test/v2/notes");
    expect(createInit?.method).toBe("POST");
    expect(JSON.parse(createInit?.body as string)).toMatchObject({
      data: {
        parent_object: "people",
        parent_record_id: "person-1",
        title: "Weekly Review",
        format: "markdown",
        content: "Updated markdown",
      },
    });
  });

  test("upsertMeetingNote preserves existing note when replacement create fails", async () => {
    const fetch = fetchMock(jsonResponse({ message: "Temporarily unavailable" }, 503));
    vi.stubGlobal("fetch", fetch);

    await expect(
      attioProvider.upsertMeetingNote(
        cfg,
        ["person-1"],
        "Weekly Review",
        "Updated markdown",
        "note-existing",
      ),
    ).rejects.toMatchObject({
      name: "CrmError",
      code: "api_error",
      status: 503,
    });

    expect(fetch).toHaveBeenCalledTimes(1);
    const [createUrl, createInit] = fetch.mock.calls[0];
    expect(createUrl).toBe("https://attio.test/v2/notes");
    expect(createInit?.method).toBe("POST");
  });

  test("api error surfaces as typed CrmError, not a throw-through", async () => {
    vi.stubGlobal(
      "fetch",
      fetchMock(jsonResponse({ message: "Unauthorized" }, 401)),
    );

    let error: unknown;
    try {
      await attioProvider.listPeople(cfg);
    } catch (caught) {
      error = caught;
    }
    expect(error).toMatchObject({
      name: "CrmError",
      code: "unauthorized",
      status: 401,
    });
    expect(error).not.toBeInstanceOf(TypeError);
    expect(getCrmProvider("attio")).toBe(attioProvider);
    expect(CrmError.unauthorized(401)).toBeInstanceOf(CrmError);
  });

  test("provider registry resolves by userSettings.crm.provider", () => {
    const userSettings = {
      crm: {
        provider: "attio",
        encryptedApiKey: "test-api-key",
      },
    };

    expect(requireCrmProvider(userSettings.crm.provider)).toBe(attioProvider);
  });
});
