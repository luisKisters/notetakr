import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import { describe, expect, test, vi } from "vitest";
import crons from "../crons";
import schema from "../schema";
import { type CrmPerson, registerCrmProvider } from "./provider";

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

const mirrorUser = makeFunctionReference<"action">("crm/mirror:mirrorUser");

function backend() {
  return convexTest({ schema, modules });
}

function registerMirrorProvider(people: CrmPerson[]) {
  const listPeople = vi.fn(async () => people);
  const upsertMeetingNote = vi.fn(async () => "unused-note-id");
  registerCrmProvider({
    providerId: "mirror-test",
    listPeople,
    upsertMeetingNote,
  });
  return { listPeople, upsertMeetingNote };
}

async function insertSettings(t: ReturnType<typeof backend>, userId = "user-a") {
  await t.run(async (ctx) => {
    await ctx.db.insert("userSettings", {
      userId,
      crm: {
        provider: "mirror-test",
        baseUrl: "https://crm.test",
        apiKey: "test-key",
      },
    });
  });
}

async function insertPerson(
  t: ReturnType<typeof backend>,
  fields: {
    userId?: string;
    email: string;
    name: string;
    company?: string;
    remoteId: string;
    provider?: string;
  },
) {
  await t.run(async (ctx) => {
    await ctx.db.insert("people", {
      userId: fields.userId ?? "user-a",
      email: fields.email,
      name: fields.name,
      company: fields.company,
      provider: fields.provider ?? "mirror-test",
      remoteId: fields.remoteId,
    });
  });
}

async function peopleRows(t: ReturnType<typeof backend>) {
  return await t.run(async (ctx) => {
    return await ctx.db.query("people").collect();
  });
}

describe("crm mirror", () => {
  test("mirror inserts new people and updates changed names", async () => {
    const provider = registerMirrorProvider([
      {
        remoteId: "person-1",
        name: "Ada Lovelace",
        email: "ADA@Example.COM",
        company: "Analytical Engines",
      },
    ]);
    const t = backend();
    await insertSettings(t);

    await t.action(mirrorUser, { userId: "user-a" });

    let rows = await peopleRows(t);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      userId: "user-a",
      email: "ada@example.com",
      name: "Ada Lovelace",
      company: "Analytical Engines",
      provider: "mirror-test",
      remoteId: "person-1",
    });

    provider.listPeople.mockResolvedValue([
      {
        remoteId: "person-1",
        name: "Ada Byron",
        email: "ada@example.com",
        company: "Difference Labs",
      },
    ]);

    await t.action(mirrorUser, { userId: "user-a" });

    rows = await peopleRows(t);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      email: "ada@example.com",
      name: "Ada Byron",
      company: "Difference Labs",
      remoteId: "person-1",
    });
  });

  test("mirror removes people whose remoteId disappeared from crm", async () => {
    registerMirrorProvider([
      {
        remoteId: "person-keep",
        name: "Grace Hopper",
        email: "grace@example.com",
      },
    ]);
    const t = backend();
    await insertSettings(t);
    await insertPerson(t, {
      remoteId: "person-keep",
      name: "Grace Hopper",
      email: "grace@example.com",
    });
    await insertPerson(t, {
      remoteId: "person-gone",
      name: "Removed Person",
      email: "removed@example.com",
    });

    await t.action(mirrorUser, { userId: "user-a" });

    const rows = await peopleRows(t);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      email: "grace@example.com",
      remoteId: "person-keep",
    });
  });

  test("mirror never touches people rows of other users", async () => {
    registerMirrorProvider([
      {
        remoteId: "person-a",
        name: "User A",
        email: "user-a@example.com",
      },
    ]);
    const t = backend();
    await insertSettings(t);
    await insertPerson(t, {
      userId: "user-b",
      remoteId: "person-gone",
      name: "Other User",
      email: "other@example.com",
    });

    await t.action(mirrorUser, { userId: "user-a" });

    const rows = await peopleRows(t);
    expect(rows).toHaveLength(2);
    expect(rows).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          userId: "user-b",
          email: "other@example.com",
          remoteId: "person-gone",
        }),
        expect.objectContaining({
          userId: "user-a",
          email: "user-a@example.com",
          remoteId: "person-a",
        }),
      ]),
    );
  });

  test("hourly cron is registered and points at the mirror function", () => {
    expect(crons.crons["mirror crm people"]).toMatchObject({
      name: "crm/mirror:mirrorAllUsers",
      schedule: {
        type: "hourly",
        minuteUTC: 0,
      },
    });
  });
});
