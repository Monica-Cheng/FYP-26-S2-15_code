# WiseWorkout — project website

Official website for **WiseWorkout**, an all-in-one fitness app: workouts, running,
cycling, calories and macros, challenges, coaches and community, with a plan that
adapts to the schedule you actually have.

Final Year Project **FYP26S215** · CSIT321 · SIM–University of Wollongong · 2025/26

The site serves the three required purposes: **marketing** (homepage),
**administrative** (weekly meeting minutes and reflective diaries at `/updates`),
and **introduction** (team and objectives at `/team` and `/about`).

## Stack

Next.js 16 (App Router) · TypeScript · Tailwind CSS v4 · Framer Motion ·
Supabase (PostgreSQL) · Lucide · deployed on Vercel.

## Running locally

```bash
npm install
npm run dev
```

Create `.env.local` in the repo root:

```bash
NEXT_PUBLIC_SUPABASE_URL=https://<project>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=sb_publishable_...   # public, ships to the browser
SUPABASE_SERVICE_ROLE_KEY=sb_secret_...            # secret, server only
ADMIN_PASSWORD=...                                 # secret, server only
```

Both Supabase key names are accepted — the legacy `ANON_KEY` / `SERVICE_ROLE_KEY`
and the current `PUBLISHABLE_KEY` / `SECRET_KEY` — so values copied straight out of
the Supabase dashboard work as-is.

`SUPABASE_SERVICE_ROLE_KEY` and `ADMIN_PASSWORD` must **never** carry a
`NEXT_PUBLIC_` prefix. Next.js inlines those into the browser bundle.

The same four variables must be set in Vercel → Settings → Environment Variables
for Production, Preview and Development.

## Database

Schema lives in `supabase/schema.sql` — four tables: `team_members`,
`weekly_updates` (reflective diaries), `meeting_minutes`, and `waitlist`.
Run it in the Supabase SQL Editor.

Row Level Security is on for all four. Minutes, diaries and team members are
publicly readable. `waitlist` accepts inserts from anyone but has **no select
policy**, so the email list cannot be read with the public key.

## Admin

Posting and editing minutes and diaries happens behind a password gate on
`/updates` (the floating **Admin** button). The password is verified server-side
at `POST /api/admin/verify` and never reaches the browser bundle. Writes go
through `/api/admin/*` using the Supabase service-role key.

## Scripts

| Command | Does |
|---|---|
| `npm run dev` | Dev server on :3000 |
| `npm run build` | Production build |
| `npm run start` | Serve the production build |
| `npm run lint` | ESLint |

## Conventions

`CONTRIBUTING.md` documents the design system, positioning, tone of voice and the
honesty rules for this project. Read it before changing copy or visuals.
