import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

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

export async function createSupabaseServerClient() {
  const cookieStore = await cookies();
  const { url, anonKey } = getPublicEnv();

  return createServerClient(url, anonKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) => {
            cookieStore.set(name, value, options);
          });
        } catch {
          // Server components can read cookies but may not be able to write them.
        }
      },
    },
  });
}
