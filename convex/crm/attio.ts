"use node";

import {
  CrmError,
  type CrmConfig,
  type CrmPerson,
  type CrmProvider,
  registerCrmProvider,
} from "./provider";
import { safeCrmFetch } from "./safeFetch";

const ATTIO_PAGE_SIZE = 500;

type AttioListPeopleResponse = {
  data?: AttioRecord[];
};

type AttioRecord = {
  id?: {
    record_id?: unknown;
  };
  values?: Record<string, unknown>;
};

type AttioNoteResponse = {
  data?: {
    id?: {
      note_id?: unknown;
    };
  };
};

type AttioNoteRef = {
  personRemoteId: string;
  noteId: string;
};

export const attioProvider: CrmProvider = {
  providerId: "attio",

  async listPeople(cfg) {
    const people: CrmPerson[] = [];
    let offset = 0;

    while (true) {
      const body = await attioRequest<AttioListPeopleResponse>(
        cfg,
        "/objects/people/records/query",
        {
          method: "POST",
          body: {
            limit: ATTIO_PAGE_SIZE,
            offset,
          },
        },
      );

      const records = body.data;
      if (!Array.isArray(records)) {
        throw CrmError.apiError(
          200,
          "Attio people response did not include data",
        );
      }

      for (const record of records) {
        people.push(...mapAttioPerson(record));
      }

      if (records.length < ATTIO_PAGE_SIZE) {
        break;
      }
      offset += ATTIO_PAGE_SIZE;
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
    const targets = uniqueNonEmpty(personRemoteIds);
    if (targets.length === 0) {
      throw CrmError.configuration(
        "Attio note requires at least one person target",
      );
    }

    const oldNoteIds = noteIdsFromRemoteNoteId(existingNoteId);
    const noteRefs: AttioNoteRef[] = [];
    for (const personRemoteId of targets) {
      noteRefs.push({
        personRemoteId,
        noteId: await createAttioNote(cfg, personRemoteId, title, markdown),
      });
    }

    await deleteOldAttioNotesBestEffort(cfg, oldNoteIds);

    return remoteNoteIdFromRefs(noteRefs);
  },
};

registerCrmProvider(attioProvider);

function noteBody(personRemoteId: string, title: string, markdown: string) {
  return {
    data: {
      parent_object: "people",
      parent_record_id: personRemoteId,
      title,
      format: "markdown",
      content: markdown,
    },
  };
}

async function createAttioNote(
  cfg: CrmConfig,
  personRemoteId: string,
  title: string,
  markdown: string,
) {
  const body = await attioRequest<AttioNoteResponse>(cfg, "/notes", {
    method: "POST",
    body: noteBody(personRemoteId, title, markdown),
  });
  return noteIdFromResponse(body);
}

async function deleteExistingAttioNote(cfg: CrmConfig, noteId: string) {
  try {
    await deleteAttioNote(cfg, noteId);
  } catch (error) {
    if (error instanceof CrmError && error.code === "not_found") {
      return;
    }
    throw error;
  }
}

async function deleteOldAttioNotesBestEffort(cfg: CrmConfig, noteIds: string[]) {
  for (const noteId of noteIds) {
    try {
      await deleteExistingAttioNote(cfg, noteId);
    } catch {
      // The replacement note is already created and should remain the stored CRM note.
    }
  }
}

async function deleteAttioNote(cfg: CrmConfig, noteId: string) {
  await attioRequest<unknown>(cfg, `/notes/${encodeURIComponent(noteId)}`, {
    method: "DELETE",
  });
}

async function attioRequest<T>(
  cfg: CrmConfig,
  path: string,
  options: {
    method: "GET" | "POST" | "PATCH" | "DELETE";
    body?: unknown;
  },
): Promise<T> {
  const url = `${attioBaseUrl(cfg)}${path}`;
  let response: Response;
  try {
    response = await safeCrmFetch(url, {
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
      error instanceof Error ? error.message : "Attio request failed",
    );
  }

  if (!response.ok) {
    throw await crmErrorFromResponse(response);
  }

  if (response.status === 204) {
    return null as T;
  }

  try {
    return (await response.json()) as T;
  } catch (error) {
    throw CrmError.apiError(
      response.status,
      error instanceof Error
        ? `Attio response was not valid JSON: ${error.message}`
        : "Attio response was not valid JSON",
    );
  }
}

function attioBaseUrl(cfg: CrmConfig) {
  const configured = normalizedString(cfg.baseUrl) ?? "https://api.attio.com";
  const trimmed = configured.replace(/\/+$/, "");
  return trimmed.endsWith("/v2") ? trimmed : `${trimmed}/v2`;
}

function requiredApiKey(cfg: CrmConfig) {
  const apiKey = normalizedString(cfg.apiKey);
  if (apiKey === undefined) {
    throw CrmError.configuration("Attio API key is not configured");
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
    return "Attio API request failed";
  }
  try {
    const parsed = JSON.parse(bodyText) as unknown;
    if (isRecord(parsed)) {
      const message = firstString([
        parsed.message,
        parsed.error,
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

function mapAttioPerson(record: AttioRecord): CrmPerson[] {
  const remoteId = normalizedString(record.id?.record_id);
  if (remoteId === undefined) {
    return [];
  }

  const values = isRecord(record.values) ? record.values : {};
  const emails = emailsFromValues(values.email_addresses);
  if (emails.length === 0) {
    return [];
  }

  const name = nameFromValues(values.name) ?? emails[0];
  const company = companyFromValues(values.company);
  return emails.map((email) => ({
    remoteId,
    name,
    email,
    ...(company === undefined ? {} : { company }),
  }));
}

function emailsFromValues(value: unknown) {
  return uniqueNonEmpty(
    valuesArray(value)
      .map((item) => {
        if (typeof item === "string") {
          return normalizedEmail(item);
        }
        if (!isRecord(item)) {
          return undefined;
        }
        return firstString([
          normalizedEmail(item.email_address),
          normalizedEmail(item.original_email_address),
          normalizedEmail(item.value),
        ]);
      })
      .filter((email) => email !== undefined),
  );
}

function nameFromValues(value: unknown) {
  for (const item of valuesArray(value)) {
    if (typeof item === "string") {
      const name = normalizedString(item);
      if (name !== undefined) {
        return name;
      }
      continue;
    }
    if (!isRecord(item)) {
      continue;
    }

    const name = firstString([
      item.full_name,
      [item.first_name, item.last_name]
        .map((part) => normalizedString(part))
        .filter((part) => part !== undefined)
        .join(" "),
      item.value,
    ]);
    if (name !== undefined) {
      return name;
    }
  }
  return undefined;
}

function companyFromValues(value: unknown) {
  for (const item of valuesArray(value)) {
    if (typeof item === "string") {
      const company = normalizedString(item);
      if (company !== undefined) {
        return company;
      }
      continue;
    }
    if (!isRecord(item)) {
      continue;
    }

    const company = firstString([
      item.name,
      item.title,
      item.value,
      item.company_name,
    ]);
    if (company !== undefined) {
      return company;
    }
  }
  return undefined;
}

function noteIdFromResponse(body: AttioNoteResponse) {
  const id = normalizedString(body.data?.id?.note_id);
  if (id === undefined) {
    throw CrmError.apiError(
      200,
      "Attio note response did not include data.id.note_id",
    );
  }
  return id;
}

function remoteNoteIdFromRefs(refs: AttioNoteRef[]) {
  if (refs.length === 1) {
    return refs[0].noteId;
  }
  return JSON.stringify({
    provider: "attio",
    notes: refs,
  });
}

function noteIdsFromRemoteNoteId(remoteNoteId: string | undefined) {
  const normalized = normalizedString(remoteNoteId);
  if (normalized === undefined) {
    return [];
  }

  try {
    const parsed = JSON.parse(normalized) as unknown;
    if (!isRecord(parsed) || parsed.provider !== "attio") {
      return [normalized];
    }
    const notes = Array.isArray(parsed.notes) ? parsed.notes : [];
    const noteIds = notes
      .map((note) => (isRecord(note) ? normalizedString(note.noteId) : undefined))
      .filter((noteId) => noteId !== undefined);
    return uniqueNonEmpty(noteIds);
  } catch {
    return [normalized];
  }
}

function valuesArray(value: unknown) {
  return Array.isArray(value) ? value : [];
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
