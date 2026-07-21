import {
  CrmError,
  type CrmConfig,
  type CrmPerson,
  type CrmProvider,
  registerCrmProvider,
} from "./provider";

type TwentyListPeopleResponse = {
  data?: {
    people?: TwentyPerson[];
  };
  pageInfo?: {
    hasNextPage?: boolean;
    endCursor?: string;
  };
};

type TwentyPerson = {
  id?: unknown;
  name?: unknown;
  emails?: unknown;
  company?: unknown;
};

type TwentyNoteResponse = {
  data?: {
    createNote?: { id?: unknown };
    updateNote?: { id?: unknown };
  };
};

type TwentyNoteTargetResponse = {
  data?: {
    createNoteTarget?: { id?: unknown };
  };
};

type TwentyNoteTargetsResponse = {
  data?: {
    noteTargets?: Array<{
      noteId?: unknown;
      personId?: unknown;
    }>;
  };
  pageInfo?: {
    hasNextPage?: boolean;
    endCursor?: string;
  };
};

export const twentyProvider: CrmProvider = {
  providerId: "twenty",

  async listPeople(cfg) {
    const people: CrmPerson[] = [];
    let startingAfter: string | undefined;

    while (true) {
      const body = await twentyRequest<TwentyListPeopleResponse>(
        cfg,
        "/people",
        {
          method: "GET",
          query: {
            limit: "60",
            depth: "1",
            ...(startingAfter === undefined
              ? {}
              : { starting_after: startingAfter }),
          },
        },
      );

      const records = body.data?.people;
      if (!Array.isArray(records)) {
        throw CrmError.apiError(
          200,
          "Twenty people response did not include data.people",
        );
      }

      for (const record of records) {
        people.push(...mapTwentyPerson(record));
      }

      const hasNextPage = body.pageInfo?.hasNextPage === true;
      const endCursor = normalizedString(body.pageInfo?.endCursor);
      if (!hasNextPage || endCursor === undefined) {
        break;
      }
      startingAfter = endCursor;
    }

    return people;
  },

  async upsertMeetingNote(
    cfg,
    personRemoteIds,
    title,
    markdown,
    existingNoteId,
  ) {
    if (existingNoteId !== undefined && existingNoteId.trim() !== "") {
      const body = await twentyRequest<TwentyNoteResponse>(
        cfg,
        `/notes/${encodeURIComponent(existingNoteId)}`,
        {
          method: "PATCH",
          body: noteBody(title, markdown),
        },
      );
      const noteId = noteIdFromResponse(body, "updateNote");
      await ensureNoteTargets(cfg, noteId, personRemoteIds);
      return noteId;
    }

    const body = await twentyRequest<TwentyNoteResponse>(cfg, "/notes", {
      method: "POST",
      body: noteBody(title, markdown),
    });
    const noteId = noteIdFromResponse(body, "createNote");

    for (const personRemoteId of uniqueNonEmpty(personRemoteIds)) {
      await createNoteTarget(cfg, noteId, personRemoteId);
    }

    return noteId;
  },
};

registerCrmProvider(twentyProvider);

function noteBody(title: string, markdown: string) {
  return {
    title,
    body: markdown,
    bodyV2: {
      blocknote: markdown,
      markdown,
    },
  };
}

async function ensureNoteTargets(
  cfg: CrmConfig,
  noteId: string,
  personRemoteIds: string[],
) {
  const wanted = uniqueNonEmpty(personRemoteIds);
  if (wanted.length === 0) {
    return;
  }
  const existing = await noteTargetPersonIdsForNote(cfg, noteId);
  for (const personRemoteId of wanted) {
    if (existing.has(personRemoteId)) {
      continue;
    }
    await createNoteTarget(cfg, noteId, personRemoteId);
  }
}

async function noteTargetPersonIdsForNote(cfg: CrmConfig, noteId: string) {
  const personIds = new Set<string>();
  let startingAfter: string | undefined;

  while (true) {
    const body = await twentyRequest<TwentyNoteTargetsResponse>(
      cfg,
      "/noteTargets",
      {
        method: "GET",
        query: {
          limit: "60",
          depth: "1",
          ...(startingAfter === undefined
            ? {}
            : { starting_after: startingAfter }),
        },
      },
    );

    const records = body.data?.noteTargets;
    if (!Array.isArray(records)) {
      throw CrmError.apiError(
        200,
        "Twenty note targets response did not include data.noteTargets",
      );
    }
    for (const target of records) {
      const targetNoteId = normalizedString(target.noteId);
      const personId = normalizedString(target.personId);
      if (targetNoteId === noteId && personId !== undefined) {
        personIds.add(personId);
      }
    }

    const hasNextPage = body.pageInfo?.hasNextPage === true;
    const endCursor = normalizedString(body.pageInfo?.endCursor);
    if (!hasNextPage || endCursor === undefined) {
      break;
    }
    startingAfter = endCursor;
  }

  return personIds;
}

async function createNoteTarget(
  cfg: CrmConfig,
  noteId: string,
  personRemoteId: string,
) {
  await twentyRequest<TwentyNoteTargetResponse>(cfg, "/noteTargets", {
    method: "POST",
    body: {
      noteId,
      personId: personRemoteId,
    },
  });
}

async function twentyRequest<T>(
  cfg: CrmConfig,
  path: string,
  options: {
    method: "GET" | "POST" | "PATCH" | "DELETE";
    query?: Record<string, string>;
    body?: unknown;
  },
): Promise<T> {
  const url = twentyUrl(cfg, path, options.query);
  let response: Response;
  try {
    response = await fetch(url, {
      method: options.method,
      headers: {
        Authorization: `Bearer ${requiredApiKey(cfg)}`,
        "Content-Type": "application/json",
      },
      body:
        options.body === undefined ? undefined : JSON.stringify(options.body),
    });
  } catch (error) {
    if (error instanceof CrmError) {
      throw error;
    }
    throw CrmError.network(
      error instanceof Error ? error.message : "Twenty request failed",
    );
  }

  if (!response.ok) {
    throw await crmErrorFromResponse(response);
  }

  try {
    return (await response.json()) as T;
  } catch (error) {
    throw CrmError.apiError(
      response.status,
      error instanceof Error
        ? `Twenty response was not valid JSON: ${error.message}`
        : "Twenty response was not valid JSON",
    );
  }
}

function twentyUrl(
  cfg: CrmConfig,
  path: string,
  query: Record<string, string> | undefined,
) {
  const url = new URL(`${restBaseUrl(cfg)}${path}`);
  for (const [key, value] of Object.entries(query ?? {})) {
    url.searchParams.set(key, value);
  }
  return url.toString();
}

function restBaseUrl(cfg: CrmConfig) {
  const baseUrl = normalizedString(cfg.baseUrl);
  if (baseUrl === undefined) {
    throw CrmError.configuration("Twenty base URL is not configured");
  }
  const trimmed = baseUrl.replace(/\/+$/, "");
  return trimmed.endsWith("/rest") ? trimmed : `${trimmed}/rest`;
}

function requiredApiKey(cfg: CrmConfig) {
  const apiKey = normalizedString(cfg.apiKey);
  if (apiKey === undefined) {
    throw CrmError.configuration("Twenty API key is not configured");
  }
  return apiKey;
}

async function crmErrorFromResponse(response: Response) {
  const message = await response.text().catch(() => "");
  if (response.status === 401 || response.status === 403) {
    return CrmError.unauthorized(response.status, readableError(message));
  }
  if (response.status === 404) {
    return CrmError.notFound(response.status, readableError(message));
  }
  return CrmError.apiError(response.status, readableError(message));
}

function readableError(bodyText: string) {
  if (bodyText.trim() === "") {
    return "Twenty API request failed";
  }
  try {
    const parsed = JSON.parse(bodyText) as unknown;
    if (isRecord(parsed)) {
      const message = firstString([
        parsed.message,
        Array.isArray(parsed.errors) && isRecord(parsed.errors[0])
          ? parsed.errors[0].message
          : undefined,
      ]);
      if (message !== undefined) {
        return message;
      }
    }
  } catch {
    return bodyText;
  }
  return bodyText;
}

function mapTwentyPerson(record: TwentyPerson): CrmPerson[] {
  const remoteId = normalizedString(record.id);
  if (remoteId === undefined) {
    return [];
  }

  const emails = emailsFromRecord(record.emails);
  if (emails.length === 0) {
    return [];
  }

  const name = nameFromRecord(record.name) ?? emails[0];
  const company = companyFromRecord(record.company);
  return emails.map((email) => ({
    remoteId,
    name,
    email,
    ...(company === undefined ? {} : { company }),
  }));
}

function emailsFromRecord(value: unknown) {
  if (!isRecord(value)) {
    return [];
  }

  const emails = [
    normalizedEmail(value.primaryEmail),
    ...(Array.isArray(value.additionalEmails)
      ? value.additionalEmails.map((email) => normalizedEmail(email))
      : []),
  ];
  return uniqueNonEmpty(emails.filter((email) => email !== undefined));
}

function nameFromRecord(value: unknown) {
  if (typeof value === "string") {
    return normalizedString(value);
  }
  if (!isRecord(value)) {
    return undefined;
  }

  return firstString([
    [value.firstName, value.lastName]
      .map((part) => normalizedString(part))
      .filter((part) => part !== undefined)
      .join(" "),
    value.fullName,
  ]);
}

function companyFromRecord(value: unknown) {
  if (typeof value === "string") {
    return normalizedString(value);
  }
  if (!isRecord(value)) {
    return undefined;
  }
  return firstString([value.name, value.displayName]);
}

function noteIdFromResponse(
  body: TwentyNoteResponse,
  key: "createNote" | "updateNote",
) {
  const id = normalizedString(body.data?.[key]?.id);
  if (id === undefined) {
    throw CrmError.apiError(
      200,
      `Twenty note response did not include data.${key}.id`,
    );
  }
  return id;
}

function uniqueNonEmpty(values: Array<string | undefined>) {
  return Array.from(
    new Set(
      values
        .map((value) => normalizedString(value))
        .filter((value) => value !== undefined),
    ),
  );
}

function firstString(values: unknown[]) {
  for (const value of values) {
    const normalized = normalizedString(value);
    if (normalized !== undefined) {
      return normalized;
    }
  }
  return undefined;
}

function normalizedEmail(value: unknown) {
  return normalizedString(value)?.toLowerCase();
}

function normalizedString(value: unknown) {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed === "" ? undefined : trimmed;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
