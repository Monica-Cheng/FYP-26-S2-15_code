create extension if not exists pgcrypto;

create table if not exists public.team_members (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  role text not null,
  bio text,
  image_url text,
  display_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.weekly_updates (
  id uuid primary key default gen_random_uuid(),
  week_label text not null,
  title text not null,
  summary text,
  body text not null,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.meeting_minutes (
  id uuid primary key default gen_random_uuid(),
  week_label text not null,
  meeting_date date not null,
  meeting_time text,
  attendees text[] not null default '{}',
  meeting_objectives text[] not null default '{}',
  agenda text[] not null default '{}',
  notes text not null,
  key_decisions text[] not null default '{}',
  action_items text[] not null default '{}',
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.waitlist (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists team_members_display_order_idx
  on public.team_members (display_order asc, created_at asc);

create index if not exists weekly_updates_created_at_idx
  on public.weekly_updates (created_at desc);

create index if not exists meeting_minutes_meeting_date_idx
  on public.meeting_minutes (meeting_date desc);

alter table public.team_members enable row level security;
alter table public.weekly_updates enable row level security;
alter table public.meeting_minutes enable row level security;
alter table public.waitlist enable row level security;

drop policy if exists "Public can view team members" on public.team_members;
create policy "Public can view team members"
  on public.team_members
  for select
  using (true);

drop policy if exists "Public can view weekly updates" on public.weekly_updates;
create policy "Public can view weekly updates"
  on public.weekly_updates
  for select
  using (true);

drop policy if exists "Public can view meeting minutes" on public.meeting_minutes;
create policy "Public can view meeting minutes"
  on public.meeting_minutes
  for select
  using (true);

-- Waitlist: anyone may sign up, nobody may read the list back.
-- There is deliberately NO select policy — with RLS on, that means the email
-- list is unreadable through the public key. Read it in the Supabase dashboard.
drop policy if exists "Anyone can join the waitlist" on public.waitlist;
create policy "Anyone can join the waitlist"
  on public.waitlist
  for insert
  with check (true);
