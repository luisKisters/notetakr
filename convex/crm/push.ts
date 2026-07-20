import { v } from "convex/values";
import { action } from "../_generated/server";

export const pushMeetingToCrm = action({
  args: {
    meetingId: v.id("meetings"),
  },
  returns: v.object({
    skipped: v.boolean(),
  }),
  handler: async () => {
    return { skipped: true };
  },
});
