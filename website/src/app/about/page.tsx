import type { Metadata } from "next";
import AboutPageClient from "./AboutPageClient";

export const metadata: Metadata = {
  title: "About — WiseWorkout",
  description:
    "Learn about WiseWorkout — a Final Year Project by SIM CSIT321 students building an AI-powered fitness companion.",
};

export default function AboutPage() {
  return <AboutPageClient />;
}
