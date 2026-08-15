import { NextResponse } from "next/server";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { checkAdminPassword } from "@/lib/admin-auth";
import { normalizeWeekLabel } from "@/lib/week-label";

async function parseRequestBody(req: Request) {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return { error: NextResponse.json({ error: "Invalid request body" }, { status: 400 }) };
  }

  if (!body || typeof body !== "object") {
    return { error: NextResponse.json({ error: "Invalid request body" }, { status: 400 }) };
  }

  return { data: body as Record<string, unknown> };
}

function parsePayload(data: Record<string, unknown>) {
  const week_label = normalizeWeekLabel(String(data.week_label ?? ""));
  const meeting_date = String(data.meeting_date ?? "").trim();
  const meeting_time = String(data.meeting_time ?? "").trim() || null;
  const notes = String(data.notes ?? "").trim();

  if (!week_label || !meeting_date || !notes) return null;

  const rawAttendees = data.attendees;
  const rawObjectives = data.meeting_objectives;
  const rawAgenda = data.agenda;
  const rawKeyDecisions = data.key_decisions;
  const rawActionItems = data.action_items;

  const attendees = Array.isArray(rawAttendees)
    ? rawAttendees.map(String).filter(Boolean)
    : String(rawAttendees ?? "")
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);

  const meeting_objectives = Array.isArray(rawObjectives)
    ? rawObjectives.map(String).filter(Boolean)
    : String(rawObjectives ?? "")
        .split("\n")
        .map((s) => s.trim())
        .filter(Boolean);

  const agenda = Array.isArray(rawAgenda)
    ? rawAgenda.map(String).filter(Boolean)
    : String(rawAgenda ?? "")
        .split("\n")
        .map((s) => s.trim())
        .filter(Boolean);

  const key_decisions = Array.isArray(rawKeyDecisions)
    ? rawKeyDecisions.map(String).filter(Boolean)
    : String(rawKeyDecisions ?? "")
        .split("\n")
        .map((s) => s.trim())
        .filter(Boolean);

  const action_items = Array.isArray(rawActionItems)
    ? rawActionItems.map(String).filter(Boolean)
    : String(rawActionItems ?? "")
        .split("\n")
        .map((s) => s.trim())
        .filter(Boolean);

  return {
    week_label,
    meeting_date,
    meeting_time,
    attendees,
    meeting_objectives,
    agenda,
    notes,
    key_decisions,
    action_items,
  };
}

export async function POST(req: Request) {
  const parsed = await parseRequestBody(req);
  if (parsed.error) return parsed.error;

  const data = parsed.data;
  const authError = checkAdminPassword(data);
  if (authError) return authError;

  const payload = parsePayload(data);
  if (!payload) {
    return NextResponse.json({ error: "Missing required fields" }, { status: 400 });
  }

  const supabase = createSupabaseAdminClient();

  const { error } = await supabase.from("meeting_minutes").insert(payload);

  if (error) {
    console.error("Meeting minutes insert error:", error.message);
    return NextResponse.json({ error: "Failed to save" }, { status: 500 });
  }

  return NextResponse.json({ success: true });
}

export async function PUT(req: Request) {
  const parsed = await parseRequestBody(req);
  if (parsed.error) return parsed.error;

  const data = parsed.data;
  const authError = checkAdminPassword(data);
  if (authError) return authError;

  const id = String(data.id ?? "").trim();
  const payload = parsePayload(data);
  if (!id || !payload) {
    return NextResponse.json({ error: "Missing required fields" }, { status: 400 });
  }

  const supabase = createSupabaseAdminClient();
  const { error } = await supabase
    .from("meeting_minutes")
    .update(payload)
    .eq("id", id);

  if (error) {
    console.error("Meeting minutes update error:", error.message);
    return NextResponse.json({ error: "Failed to update" }, { status: 500 });
  }

  return NextResponse.json({ success: true });
}

export async function DELETE(req: Request) {
  const parsed = await parseRequestBody(req);
  if (parsed.error) return parsed.error;

  const data = parsed.data;
  const authError = checkAdminPassword(data);
  if (authError) return authError;

  const id = String(data.id ?? "").trim();
  if (!id) {
    return NextResponse.json({ error: "Missing entry id" }, { status: 400 });
  }

  const supabase = createSupabaseAdminClient();
  const { error } = await supabase.from("meeting_minutes").delete().eq("id", id);

  if (error) {
    console.error("Meeting minutes delete error:", error.message);
    return NextResponse.json({ error: "Failed to delete" }, { status: 500 });
  }

  return NextResponse.json({ success: true });
}
