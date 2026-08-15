import { NextResponse } from "next/server";
import { checkAdminPassword } from "@/lib/admin-auth";

/**
 * Unlocks the admin panel. The check lives here rather than in the client so the
 * password never has to be shipped to the browser to be compared against.
 */
export async function POST(req: Request) {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body" }, { status: 400 });
  }

  const authError = checkAdminPassword((body ?? {}) as Record<string, unknown>);
  if (authError) return authError;

  return NextResponse.json({ success: true });
}
