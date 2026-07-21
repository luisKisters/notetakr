import { v } from "convex/values";
import { internal } from "./_generated/api";
import { internalAction, internalMutation, internalQuery } from "./_generated/server";
import { env } from "./env";

const transcriptSegment = v.object({
  seq: v.number(),
  startMs: v.number(),
  speaker: v.optional(v.string()),
  text: v.string(),
});

const summaryResult = v.object({
  status: v.union(v.literal("ready"), v.literal("failed"), v.literal("stale")),
  summary: v.optional(v.string()),
});

// Verified against OpenRouter on 2026-07-20: Kimi K2.7 is exposed as
// the coding-focused model slug `moonshotai/kimi-k2.7-code`.
const DEFAULT_SUMMARY_MODEL = "moonshotai/kimi-k2.7-code";

type TranscriptSegment = {
  seq: number;
  speaker?: string;
  text: string;
};

export const loadSummaryInput = internalQuery({
  args: {
    meetingId: v.id("meetings"),
  },
  returns: v.union(
    v.null(),
    v.object({
      title: v.string(),
      contentHash: v.string(),
      transcriptSegments: v.array(transcriptSegment),
    }),
  ),
  handler: async (ctx, { meetingId }) => {
    const meeting = await ctx.db.get(meetingId);
    if (meeting === null) {
      return null;
    }

    const segments = await ctx.db
      .query("transcriptSegments")
      .withIndex("by_meeting", (q) => q.eq("meetingId", meetingId))
      .collect();

    return {
      title: meeting.title,
      contentHash: meeting.contentHash,
      transcriptSegments: segments
        .map((segment) => ({
          seq: segment.seq,
          startMs: segment.startMs,
          speaker: segment.speaker,
          text: segment.text,
        }))
        .sort((a, b) => a.seq - b.seq),
    };
  },
});

export const writeSummaryReady = internalMutation({
  args: {
    meetingId: v.id("meetings"),
    expectedContentHash: v.string(),
    summary: v.string(),
  },
  returns: v.boolean(),
  handler: async (ctx, { meetingId, expectedContentHash, summary }) => {
    const meeting = await ctx.db.get(meetingId);
    if (meeting === null || meeting.contentHash !== expectedContentHash) {
      return false;
    }
    await ctx.db.patch(meetingId, {
      summary,
      summaryStatus: "ready",
      summaryError: undefined,
    });
    return true;
  },
});

export const writeSummaryFailed = internalMutation({
  args: {
    meetingId: v.id("meetings"),
    expectedContentHash: v.string(),
    message: v.string(),
  },
  returns: v.boolean(),
  handler: async (ctx, { meetingId, expectedContentHash, message }) => {
    const meeting = await ctx.db.get(meetingId);
    if (meeting === null || meeting.contentHash !== expectedContentHash) {
      return false;
    }
    await ctx.db.patch(meetingId, {
      summaryStatus: "failed",
      summaryError: message,
    });
    return true;
  },
});

export const summarizeMeeting = internalAction({
  args: {
    meetingId: v.id("meetings"),
  },
  returns: summaryResult,
  handler: async (ctx, { meetingId }) => {
    const input = await ctx.runQuery(internal.summarize.loadSummaryInput, {
      meetingId,
    });

    if (input === null) {
      return { status: "failed" as const };
    }

    try {
      const summary = await summarizeWithOpenRouter({
        apiKey: env.OPENROUTER_API_KEY,
        model: env.SUMMARY_MODEL ?? DEFAULT_SUMMARY_MODEL,
        title: input.title,
        transcriptSegments: input.transcriptSegments,
      });

      const wroteSummary = await ctx.runMutation(internal.summarize.writeSummaryReady, {
        meetingId,
        expectedContentHash: input.contentHash,
        summary,
      });
      if (!wroteSummary) {
        return { status: "stale" as const };
      }
      await ctx.scheduler.runAfter(0, internal.crm.push.pushMeetingToCrm, {
        meetingId,
      });

      return { status: "ready" as const, summary };
    } catch (error) {
      const wroteFailure = await ctx.runMutation(internal.summarize.writeSummaryFailed, {
        meetingId,
        expectedContentHash: input.contentHash,
        message: summaryErrorMessage(error),
      });
      if (!wroteFailure) {
        return { status: "stale" as const };
      }
      return { status: "failed" as const };
    }
  },
});

async function summarizeWithOpenRouter({
  apiKey,
  model,
  title,
  transcriptSegments,
}: {
  apiKey: string | undefined;
  model: string;
  title: string;
  transcriptSegments: TranscriptSegment[];
}) {
  if (apiKey === undefined || apiKey.trim() === "") {
    throw new Error("OPENROUTER_API_KEY is not configured");
  }
  if (transcriptSegments.length === 0) {
    throw new Error("Cannot summarize a meeting without transcript segments");
  }

  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "X-Title": "NoteTakr",
    },
    body: JSON.stringify({
      model,
      messages: [
        {
          role: "system",
          content:
            "Summarize meeting transcripts into concise notes with decisions, action items, and open questions.",
        },
        {
          role: "user",
          content: [
            `Meeting title: ${title}`,
            "",
            "Transcript:",
            formatTranscript(transcriptSegments),
          ].join("\n"),
        },
      ],
      temperature: 0.2,
    }),
  });

  if (!response.ok) {
    throw new Error(`OpenRouter summary request failed: ${response.status}`);
  }

  const body = (await response.json()) as {
    choices?: Array<{ message?: { content?: unknown } }>;
  };
  const content = body.choices?.[0]?.message?.content;
  if (typeof content !== "string" || content.trim() === "") {
    throw new Error("OpenRouter summary response did not include content");
  }

  return content.trim();
}

function formatTranscript(segments: TranscriptSegment[]) {
  return segments
    .map((segment) => {
      const text = segment.text.trim();
      if (segment.speaker === undefined || segment.speaker.trim() === "") {
        return text;
      }
      return `${segment.speaker.trim()}: ${text}`;
    })
    .join("\n");
}

function summaryErrorMessage(error: unknown) {
  if (error instanceof Error && error.message.trim() !== "") {
    return error.message;
  }
  return "Cloud summary generation failed.";
}
