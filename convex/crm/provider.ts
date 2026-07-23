export type CrmConfig = {
  provider: string;
  baseUrl?: string;
  apiKey?: string;
};

export type CrmPerson = {
  remoteId: string;
  name: string;
  email: string;
  company?: string;
};

export type CrmErrorCode =
  | "configuration"
  | "unauthorized"
  | "not_found"
  | "api_error"
  | "network";

export class CrmError extends Error {
  readonly code: CrmErrorCode;
  readonly status?: number;

  constructor(code: CrmErrorCode, message: string, status?: number) {
    super(message);
    this.name = "CrmError";
    this.code = code;
    this.status = status;
  }

  static configuration(message: string) {
    return new CrmError("configuration", message);
  }

  static unauthorized(status = 401, message = "CRM credentials were rejected") {
    return new CrmError("unauthorized", message, status);
  }

  static notFound(status = 404, message = "CRM resource was not found") {
    return new CrmError("not_found", message, status);
  }

  static apiError(status: number, message: string) {
    return new CrmError("api_error", message, status);
  }

  static network(message: string) {
    return new CrmError("network", message);
  }
}

export interface CrmProvider {
  readonly providerId: string;
  listPeople(cfg: CrmConfig): Promise<CrmPerson[]>;
  upsertMeetingNote(
    cfg: CrmConfig,
    personRemoteIds: string[],
    title: string,
    markdown: string,
    existingNoteId?: string,
  ): Promise<string>;
}

const registry = new Map<string, CrmProvider>();

export function registerCrmProvider(provider: CrmProvider) {
  registry.set(provider.providerId, provider);
}

export function getCrmProvider(providerId: string) {
  return registry.get(providerId);
}

export function requireCrmProvider(providerId: string) {
  const provider = getCrmProvider(providerId);
  if (provider === undefined) {
    throw CrmError.configuration(`Unsupported CRM provider: ${providerId}`);
  }
  return provider;
}
