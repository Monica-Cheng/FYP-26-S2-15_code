// Server-only. NEVER import this into a "use client" file.
import { timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";

/**
 * `ADMIN_PASSWORD` must never carry a NEXT_PUBLIC_ prefix. Next.js inlines
 * NEXT_PUBLIC_* values into the browser bundle, which would let anyone read the
 * password out of DevTools and post to the admin routes themselves.
 */
function equals(supplied: string, expected: string) {
  const a = Buffer.from(supplied);
  const b = Buffer.from(expected);
  // timingSafeEqual throws on length mismatch, so compare lengths first.
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

/**
 * Returns an error response when the request is not authorised, or null when it
 * is. Fails closed: if ADMIN_PASSWORD is unset, nobody gets in.
 */
export function checkAdminPassword(data: Record<string, unknown>) {
  const expected = process.env.ADMIN_PASSWORD ?? "";

  if (!expected) {
    console.error("ADMIN_PASSWORD is not set — admin writes are disabled.");
    return NextResponse.json(
      { error: "Admin is not configured on this server." },
      { status: 503 },
    );
  }

  if (!equals(String(data.password ?? ""), expected)) {
    return NextResponse.json({ error: "Incorrect password" }, { status: 401 });
  }

  return null;
}
