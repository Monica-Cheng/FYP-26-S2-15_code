/*
  Run this SQL in your Supabase SQL editor:

  CREATE TABLE IF NOT EXISTS meeting_minutes (
    id uuid default gen_random_uuid() primary key,
    week_label text not null,
    meeting_date date not null,
    meeting_time text,
    attendees text[],
    meeting_objectives text[],
    agenda text[],
    notes text not null,
    key_decisions text[],
    action_items text[],
    created_at timestamptz default now()
  );
  ALTER TABLE meeting_minutes ENABLE ROW LEVEL SECURITY;
  CREATE POLICY "Public read" ON meeting_minutes FOR SELECT USING (true);

  CREATE TABLE IF NOT EXISTS weekly_updates (
    id uuid default gen_random_uuid() primary key,
    week_label text not null,
    title text not null,
    summary text,
    body text not null,
    created_at timestamptz default now()
  );
  ALTER TABLE weekly_updates ENABLE ROW LEVEL SECURITY;
  CREATE POLICY "Public read" ON weekly_updates FOR SELECT USING (true);
*/

import type { Metadata } from "next";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import UpdatesPageClient from "./UpdatesPageClient";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Updates — WiseWorkout",
  description:
    "Weekly meeting minutes and reflective diaries from FYP Group FYP26S215.",
};

export interface MeetingMinute {
  id: string;
  week_label: string;
  meeting_date: string;
  meeting_time: string | null;
  attendees: string[];
  meeting_objectives: string[];
  agenda: string[];
  notes: string;
  key_decisions: string[];
  action_items: string[];
  created_at: string;
}

export interface DiaryEntry {
  id: string;
  week_label: string;
  title: string;
  summary: string | null;
  body: string;
  created_at: string;
}

export default async function UpdatesPage() {
  const supabase = await createSupabaseServerClient();

  const [minutesResult, diaryResult] = await Promise.all([
    supabase
      .from("meeting_minutes")
      .select("*")
      .order("meeting_date", { ascending: false }),
    supabase
      .from("weekly_updates")
      .select("*")
      .order("created_at", { ascending: false }),
  ]);

  const meetingMinutes: MeetingMinute[] = (minutesResult.data ?? []) as MeetingMinute[];
  const diaryEntries: DiaryEntry[] = (diaryResult.data ?? []) as DiaryEntry[];

  return (
    <UpdatesPageClient
      meetingMinutes={meetingMinutes}
      diaryEntries={diaryEntries}
    />
  );
}
