import { createBrowserClient } from "@supabase/ssr";

function getPublicEnv() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  // Supabase renamed the anon key to the "publishable" key (sb_publishable_…).
  // Accept either name so the values copied straight out of the dashboard work.
  const anonKey =
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ??
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!url || !anonKey) {
    throw new Error(
      "Missing NEXT_PUBLIC_SUPABASE_URL, or NEXT_PUBLIC_SUPABASE_ANON_KEY / NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY.",
    );
  }

  return { url, anonKey };
}

export function createSupabaseBrowserClient() {
  const { url, anonKey } = getPublicEnv();

  return createBrowserClient(url, anonKey);
}
