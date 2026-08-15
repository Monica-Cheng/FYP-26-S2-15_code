import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export async function POST(req: Request) {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body" }, { status: 400 });
  }

  const email =
    body && typeof body === "object" && "email" in body
      ? String((body as { email: unknown }).email).trim().toLowerCase()
      : "";

  if (!email || !EMAIL_RE.test(email)) {
    return NextResponse.json({ error: "Invalid email address" }, { status: 400 });
  }

  const supabase = await createSupabaseServerClient();

  const { error } = await supabase.from("waitlist").insert({ email });

  if (error) {
    // Postgres unique violation
    if (error.code === "23505") {
      return NextResponse.json({ error: "Already signed up" }, { status: 409 });
    }
    console.error("Waitlist insert error:", error.message);
    return NextResponse.json({ error: "Failed to sign up" }, { status: 500 });
  }

  return NextResponse.json({ success: true });
}
