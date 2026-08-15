/*
  Run this SQL in your Supabase SQL editor to create the team_members table:

  CREATE TABLE IF NOT EXISTS team_members (
    id uuid default gen_random_uuid() primary key,
    name text not null,
    role text not null,
    bio text,
    responsibilities text[],
    fun_fact text,
    image_url text,
    display_order int default 0
  );

  -- Enable Row Level Security (public read-only)
  ALTER TABLE team_members ENABLE ROW LEVEL SECURITY;
  CREATE POLICY "Public read" ON team_members FOR SELECT USING (true);
*/

import type { Metadata } from "next";
import TeamPageClient from "./TeamPageClient";

export const metadata: Metadata = {
  title: "Team — WiseWorkout",
  description:
    "Meet the FYP26S215 team behind WiseWorkout — SIM CSIT321 students building an AI-powered fitness app.",
};

export default function TeamPage() {
  return <TeamPageClient />;
}
