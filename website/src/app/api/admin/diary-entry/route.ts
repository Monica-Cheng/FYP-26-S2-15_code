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

export async function POST(req: Request) {
  const parsed = await parseRequestBody(req);
  if (parsed.error) return parsed.error;

  const data = parsed.data;
  const authError = checkAdminPassword(data);
  if (authError) return authError;

  const week_label = normalizeWeekLabel(String(data.week_label ?? ""));
  const title = String(data.name ?? data.title ?? "").trim();
  const body_text = String(data.body ?? "").trim();

  if (!week_label || !title || !body_text) {
    return NextResponse.json({ error: "Missing required fields" }, { status: 400 });
  }

  const supabase = createSupabaseAdminClient();

  const { error } = await supabase.from("weekly_updates").insert({
    week_label,
    title,
    body: body_text,
  });

  if (error) {
    console.error("Diary entry insert error:", error.message);
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
  const week_label = normalizeWeekLabel(String(data.week_label ?? ""));
  const title = String(data.name ?? data.title ?? "").trim();
  const body_text = String(data.body ?? "").trim();

  if (!id || !week_label || !title || !body_text) {
    return NextResponse.json({ error: "Missing required fields" }, { status: 400 });
  }

  const supabase = createSupabaseAdminClient();

  const { error } = await supabase
    .from("weekly_updates")
    .update({
      week_label,
      title,
      body: body_text,
    })
    .eq("id", id);

  if (error) {
    console.error("Diary entry update error:", error.message);
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

  const { error } = await supabase.from("weekly_updates").delete().eq("id", id);

  if (error) {
    console.error("Diary entry delete error:", error.message);
    return NextResponse.json({ error: "Failed to delete" }, { status: 500 });
  }

  return NextResponse.json({ success: true });
}
