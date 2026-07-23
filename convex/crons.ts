import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

crons.hourly(
  "mirror crm people",
  { minuteUTC: 0 },
  internal.crm.mirror.mirrorAllUsers,
);

export default crons;
