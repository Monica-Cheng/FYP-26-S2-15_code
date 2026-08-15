"use client";

import Link from "next/link";
import FadeInUp from "@/components/animations/FadeInUp";
import Section, { Eyebrow } from "@/components/ui/Section";
import BrowserFrame from "@/components/ui/BrowserFrame";
import { siteConfig } from "@/content/site-config";

/* The academic page. Factual register, no marketing voice, no CTA.
   Content follows the project documentation, sections 2.2–2.6. */

const USPS = [
  {
    number: "01",
    title: "Adaptive training for real-life disruptions",
    body: "WiseWorkout is designed for the case where a schedule cannot be followed perfectly. Compress Workout shortens a scheduled session when time is limited. Missed Workout Check-in records and acknowledges a missed session. Break Mode pauses reminders and missed-session handling for a chosen number of days. An unfinished tracked gym session can be resumed. Injury-aware filtering avoids exercises associated with recorded injury areas. The intent is continuation after a disruption rather than abandonment.",
  },
  {
    number: "02",
    title: "Gym, cardio and combined training in one platform",
    body: "Gym, Cardio and Combine plans share the same planning and tracking environment. Users can follow gym-only or cardio-only sessions, build mixed multi-day routines, and complete combined sessions containing both strength exercises and cardio blocks in a single tracked workflow. Planning, session records and progress from different training styles stay in one application.",
  },
  {
    number: "03",
    title: "WiseCoach turns workout data into understandable guidance",
    body: "Two complementary forms of assistance: conversational fitness Q&A, and an automatic post-session recap. After supported gym, cardio and combined sessions the recap explains the workout in short, plain language, and can incorporate lightweight historical context such as recent comparable sessions, weekly plan adherence and streak status. The purpose is motivational interpretation, not diagnosis or medical advice.",
  },
  {
    number: "04",
    title: "Optional social accountability",
    body: "Users can build a friends network, compare weekly XP on a friends leaderboard, join public challenges, create private challenges, follow other users, and interact through a social feed of workout and nutrition posts with reactions and comments. Users who prefer to train alone retain full access to planning, tracking and coaching without depending on competitive features.",
  },
  {
    number: "05",
    title: "Injury-aware training and access to human support",
    body: "Users can record injury areas and enable injury-aware filtering so that supported workout flows avoid or warn about the associated exercises. Find a Professional lets authenticated users browse approved fitness professionals and send a coaching request. This bridges self-directed digital training and optional human support while keeping the prototype within a non-medical scope.",
  },
];

const BUSINESS_MODEL = [
  {
    title: "Ongoing cloud-service dependency",
    body: "The prototype depends on cloud-hosted services for authentication, Firestore data storage, Cloud Functions, notifications, administrator configuration and WiseCoach AI requests. A production deployment would incur recurring service and API costs as usage grows.",
  },
  {
    title: "Continuous product and content delivery",
    body: "Workout plans, exercises, challenge categories, Premium prices and AI limits are maintained centrally. A subscription model suits a product intended to keep receiving content and service improvements rather than remaining a fixed offline application.",
  },
  {
    title: "Different levels of end-user access",
    body: "The prototype supports Free and Premium entitlement states. Most core training functions remain available to Free users, while Premium differentiates selected high-cost or higher-value functions.",
  },
];

const USER_CATEGORIES = [
  {
    name: "Guest / unregistered user",
    description:
      "Has installed or opened WiseWorkout but has not authenticated.",
    goals: "Understand the purpose of the app and decide whether to register.",
    access:
      "Splash and walkthrough flow, Login, Create Account, Forgot Password. Unauthenticated routing does not expose Premium pricing, the plan catalogue, the social feed or Find a Professional.",
  },
  {
    name: "Registered end user — Free tier",
    description:
      "Uses the core planning, tracking, progress, social and coaching functions without a Premium entitlement.",
    goals:
      "Follow and adapt plans, track gym, cardio and combined training, monitor progress and nutrition, receive AI-assisted guidance, use optional social accountability.",
    access:
      "Plan browsing, Plan Match, saving and tracking plans, custom routines, Compress Workout, Missed Workout Check-in, Break Mode, injury filtering, gym and indoor/outdoor cardio tracking, combined sessions, manual activity logging, progress analytics, social features, public challenges, Find a Professional, Describe a Meal, nutrition history, post-session recaps, up to 25 typed WiseCoach messages per calendar month, up to 3 private challenges. Photo and barcode nutrition scanning are locked.",
  },
  {
    name: "Registered end user — Premium tier",
    description:
      "Carries the Premium entitlement flag. The build demonstrates access control; it does not include a live payment or renewal system.",
    goals:
      "The same complete core experience with selected usage limits removed and higher-value nutrition capture unlocked.",
    access:
      "All Free functionality, no WiseCoach typed-message cap, meal photo scanning and barcode scanning unlocked, no client-side cap on private challenge creation. Plan, adaptive-support, progress and social functions are not Premium-only.",
  },
  {
    name: "Business partner / coach",
    description:
      "A fitness professional who can apply for professional status, upload credentials and become visible after administrator approval. A basic coach–user workflow rather than a complete commercial coaching portal.",
    goals:
      "Establish a verified presence, receive coaching requests, maintain an accepted-client relationship and publish coach-authored plans.",
    access:
      "Professional application, credential upload, administrator approval and revocation, Find a Professional visibility, incoming coaching requests, accept and decline actions, a Current Clients list, coach-authored plan creation. The prototype does not provide detailed client progress views, direct plan assignment to a selected client, in-app messaging, appointment scheduling, booking or payment.",
  },
  {
    name: "System administrator",
    description:
      "An authorised internal operator managing the platform through a separate React-based web dashboard.",
    goals:
      "Maintain account safety, professional verification, platform content, moderation, configuration and operational visibility without editing the database manually.",
    access:
      "Platform overview metrics; user browsing, search and filtering; account suspend, reactivate and delete; business partner application review, approval and revocation; exercise catalogue management; official plan management; analytics; challenge records and categories; global challenge creation and deletion; social-post moderation; injury-category management; badge definitions; broadcast announcements; configurable Premium monthly and annual prices; cardio anti-cheat threshold configuration.",
  },
];

const VALUE_END_USERS = [
  "Training flexibility when real life interrupts the schedule — Compress Workout, Missed Workout Check-in and Break Mode each answer a different kind of disruption, and resume support continues an interrupted tracked session from its saved state.",
  "Gym, cardio and mixed training in a single workflow, so planning, completion records and progress stay in one application.",
  "Plain-language interpretation instead of statistics alone — ongoing Q&A plus an automatic post-session recap that adds context from recent comparable sessions, weekly adherence and streak status.",
  "Integrated nutrition, progress and social accountability within the same ecosystem.",
  "Injury-aware training with an optional pathway to approved fitness professionals, presented as support rather than medical diagnosis or referral.",
];

const METHODOLOGY = [
  {
    title: "Weekly iterations",
    body: "Work is planned and reviewed on a weekly cycle aligned to the academic calendar rather than a fixed-length sprint.",
  },
  {
    title: "Documented meetings",
    body: "Each meeting is minuted with date, attendees, agenda, key decisions and action items, then published to the Updates page.",
  },
  {
    title: "Individual reflection",
    body: "Every team member submits a weekly reflective diary recording contribution, obstacles and revised approach.",
  },
  {
    title: "Prototype before build",
    body: "Screens are designed and reviewed in Figma before implementation, so interface decisions are settled outside code.",
  },
  {
    title: "Supervisor checkpoints",
    body: "Progress is reviewed against the project plan at the checkpoints set by the CSIT321 assessment schedule.",
  },
];

const TECH_STACK = [
  { layer: "Mobile application", choice: "Flutter", note: "Single codebase for iOS and Android" },
  { layer: "Application backend", choice: "Firebase, Cloud Firestore, Cloud Functions", note: "Authentication, document store, server-side logic and notifications" },
  { layer: "AI assistance", choice: "WiseCoach service layer", note: "Conversational Q&A and automatic post-session recaps" },
  { layer: "Administration", choice: "React web dashboard", note: "Users, professional approval, content, moderation and platform configuration" },
  { layer: "Project website", choice: "Next.js (App Router), TypeScript", note: "Server-rendered routes with typed components" },
  { layer: "Website styling", choice: "Tailwind CSS, Framer Motion", note: "Token-driven styling and scroll reveals" },
  { layer: "Website data", choice: "Supabase (PostgreSQL)", note: "Stores minutes, diaries and waitlist records" },
  { layer: "Design", choice: "Figma", note: "Wireframes and high-fidelity prototypes" },
  { layer: "Hosting", choice: "Vercel", note: "Continuous deployment from the project repository" },
];

const REFERENCES = [
  "Fitbod (2026) 'How Fitbod Creates Your Workout', Fitbod Help Centre, 1 April. Available at: help.fitbod.me (Accessed: 13 August 2026).",
  "Freeletics (2024) 'Adapt Today', 27 May. Available at: freeletics.com/en/blog/posts/quick-adapt (Accessed: 13 August 2026).",
  "Hevy (2026) 'Hevy App Feature List — Workout Tracker & Gym Log App'. Available at: hevyapp.com/features (Accessed: 13 August 2026).",
  "MyFitnessPal (2024) 'How do I use the barcode scanner to log foods?', MyFitnessPal Help, 30 September. Available at: support.myfitnesspal.com (Accessed: 13 August 2026).",
  "MyFitnessPal (2026a) 'Meal Scan FAQ', MyFitnessPal Help, 22 January. Available at: support.myfitnesspal.com (Accessed: 13 August 2026).",
  "Strava (2026) 'Athlete Intelligence on Strava', Strava Support. Available at: support.strava.com (Accessed: 13 August 2026).",
];

export default function AboutPageClient() {
  const { academic, pricing } = siteConfig;

  return (
    <>
      <Section surface="light" className="pt-14">
        <FadeInUp className="max-w-3xl">
          <p className="text-meta text-steel">
            {academic.group} · {academic.course} · {academic.school} · {academic.year}
          </p>
          <h1 className="mt-4 text-display font-bold text-ink">About the project</h1>
          <p className="mt-5 max-w-[62ch] text-lede text-carbon">
            WiseWorkout is a Final Year Project undertaken for CSIT321 at SIM–University
            of Wollongong. This page records the problem the project addresses, what
            differentiates it, the business model, the user categories it serves, the
            development methodology and the technologies used.
          </p>
        </FadeInUp>
      </Section>

      {/* ── Problem ─────────────────────────────────────────────── */}
      <Section surface="linen">
        <FadeInUp className="max-w-3xl">
          <Eyebrow>Problem statement</Eyebrow>
          <h2 className="mt-3 text-heading font-bold text-ink">
            Fitness applications record training well and interpret it poorly.
          </h2>
          <p className="mt-5 max-w-[68ch] text-body text-carbon">
            Existing applications capture session data accurately but leave its
            interpretation to the user, who is presented with charts and totals and must
            independently decide what the next session should contain. Competitor research
            shows that the individual capabilities WiseWorkout uses are not unique in
            isolation: Freeletics provides adaptive session modification and personalised
            AI-supported training, Fitbod personalises strength workouts, Strava combines
            social activity tracking with AI-generated activity summaries, Hevy combines
            gym logging with progress and social features, and MyFitnessPal provides
            camera- and barcode-assisted nutrition logging. What remains unaddressed is the
            integration of these capabilities into one workflow.
          </p>
        </FadeInUp>
      </Section>

      {/* ── USPs ────────────────────────────────────────────────── */}
      <Section surface="light">
        <FadeInUp className="max-w-3xl">
          <Eyebrow>Differentiation</Eyebrow>
          <h2 className="mt-3 text-heading font-bold text-ink">Unique selling points</h2>
          <p className="mt-5 max-w-[68ch] text-body text-carbon">
            WiseWorkout positions its differentiation around the integration of adaptive
            plan support, gym/cardio/combined training, AI guidance, nutrition, social
            accountability and injury-aware safeguards within one mobile prototype.
          </p>
        </FadeInUp>

        <div className="mt-10 border-t border-silver">
          {USPS.map((usp, i) => (
            <FadeInUp key={usp.number} delay={i * 0.04}>
              <div className="grid gap-2 border-b border-silver py-7 md:grid-cols-[80px_1fr] md:gap-8">
                <p className="text-meta text-steel">{usp.number}</p>
                <div>
                  <h3 className="text-heading-sm font-semibold text-ink">{usp.title}</h3>
                  <p className="mt-2 max-w-[68ch] text-body text-carbon">{usp.body}</p>
                </div>
              </div>
            </FadeInUp>
          ))}
        </div>
      </Section>

      {/* ── Business model ──────────────────────────────────────── */}
      <Section surface="linen">
        <FadeInUp className="max-w-3xl">
          <Eyebrow>Business model</Eyebrow>
          <h2 className="mt-3 text-heading font-bold text-ink">
            Freemium subscription, delivered as a cloud service
          </h2>
          <p className="mt-5 max-w-[68ch] text-body text-carbon">
            WiseWorkout adopts a freemium subscription model with characteristics commonly
            associated with Software as a Service, rather than a one-time software
            purchase. Three reasons make this appropriate.
          </p>
        </FadeInUp>

        <div className="mt-10 border-t border-silver">
          {BUSINESS_MODEL.map((item, i) => (
            <FadeInUp key={item.title} delay={i * 0.04}>
              <div className="grid gap-2 border-b border-silver py-6 md:grid-cols-[280px_1fr] md:gap-8">
                <h3 className="text-heading-sm font-semibold text-ink">{item.title}</h3>
                <p className="max-w-[68ch] text-body text-carbon">{item.body}</p>
              </div>
            </FadeInUp>
          ))}
        </div>

        <FadeInUp delay={0.1}>
          <div className="mt-10 rounded-card border border-silver bg-white p-6">
            <h3 className="text-heading-sm font-semibold text-ink">
              Current implementation boundary
            </h3>
            <p className="mt-2 max-w-[68ch] text-body text-carbon">
              The prototype implements Free and Premium feature gating and remotely
              configurable monthly and annual Premium prices. It does <strong>not</strong>{" "}
              implement Stripe, Apple StoreKit, Google Play Billing, checkout, receipt
              validation, subscription renewal or automatic payment collection. The Upgrade
              action is presented as “Coming Soon”. A production release could connect the
              existing entitlement model to a commercial billing provider.
            </p>
          </div>
        </FadeInUp>
      </Section>

      {/* ── User categories ─────────────────────────────────────── */}
      <Section surface="light">
        <FadeInUp className="max-w-3xl">
          <Eyebrow>Target users</Eyebrow>
          <h2 className="mt-3 text-heading font-bold text-ink">User categories</h2>
          <p className="mt-5 max-w-[68ch] text-body text-carbon">
            Guest users, registered end users and business partners interact through the
            Flutter mobile application. System administrators use a separate React-based
            web dashboard.
          </p>
        </FadeInUp>

        <div className="mt-10 flex flex-col gap-4">
          {USER_CATEGORIES.map((cat, i) => (
            <FadeInUp key={cat.name} delay={i * 0.04}>
              <div className="rounded-card border border-silver bg-linen p-6">
                <h3 className="text-heading-sm font-semibold text-ink">{cat.name}</h3>
                <p className="mt-2 max-w-[68ch] text-body text-carbon">{cat.description}</p>
                <dl className="mt-4 grid gap-3 border-t border-silver pt-4 md:grid-cols-[130px_1fr] md:gap-x-8">
                  <dt className="text-meta text-steel">Primary goals</dt>
                  <dd className="max-w-[64ch] text-body text-carbon">{cat.goals}</dd>
                  <dt className="text-meta text-steel md:mt-0">System access</dt>
                  <dd className="max-w-[64ch] text-body text-carbon">{cat.access}</dd>
                </dl>
              </div>
            </FadeInUp>
          ))}
        </div>
      </Section>

      {/* ── Value propositions ──────────────────────────────────── */}
      <Section surface="linen">
        <FadeInUp className="max-w-3xl">
          <Eyebrow>Value propositions</Eyebrow>
          <h2 className="mt-3 text-heading font-bold text-ink">What each audience gets</h2>
        </FadeInUp>

        <div className="mt-10 grid gap-10 lg:grid-cols-[1.4fr_1fr] lg:gap-14">
          <FadeInUp>
            <h3 className="border-b border-silver pb-3 text-heading-sm font-semibold text-ink">
              For end users
            </h3>
            <ul className="mt-1">
              {VALUE_END_USERS.map((v) => (
                <li key={v} className="border-b border-silver py-4 text-body text-carbon">
                  {v}
                </li>
              ))}
            </ul>
          </FadeInUp>

          <FadeInUp delay={0.06}>
            <h3 className="border-b border-silver pb-3 text-heading-sm font-semibold text-ink">
              For business partners
            </h3>
            <p className="py-4 text-body text-carbon">
              A verified in-app presence and an initial pathway for receiving coaching
              requests and publishing workout content to accepted clients. The
              implementation is deliberately limited: it demonstrates professional
              onboarding and basic coach–user relationships, and does not claim
              comprehensive client management, direct plan assignment, messaging, booking
              or payment.
            </p>

            <h3 className="mt-6 border-b border-silver pb-3 text-heading-sm font-semibold text-ink">
              For the platform
            </h3>
            <p className="py-4 text-body text-carbon">
              Engagement mechanisms — XP, streaks, badges, challenges and social posting —
              combined with centralised administration of users, professional approval,
              exercises, plans, challenges, moderation and broadcasts. Premium display
              pricing, WiseCoach Free-tier limits and cardio anti-cheat thresholds are
              configurable without rebuilding the mobile app.
            </p>
          </FadeInUp>
        </div>
      </Section>

      {/* ── Free vs Premium ─────────────────────────────────────── */}
      <Section surface="light">
        <FadeInUp className="max-w-3xl">
          <Eyebrow>Feature differentiation</Eyebrow>
          <h2 className="mt-3 text-heading font-bold text-ink">Free versus Premium</h2>
          <p className="mt-5 max-w-[68ch] text-body text-carbon">
            Free users have access to most of the core fitness experience. Premium
            differentiation is concentrated in selected features rather than locking basic
            training behind a paywall. The table reflects the current implementation, not
            an intended future pricing plan.
          </p>
        </FadeInUp>

        <FadeInUp delay={0.06}>
          <div className="mt-10 overflow-x-auto">
            <table className="w-full min-w-[600px] border-collapse text-left">
              <thead>
                <tr className="border-b border-silver">
                  <th className="pb-3 pr-6 text-meta font-normal text-steel">Area</th>
                  <th className="w-[210px] pb-3 pr-6 text-meta font-normal text-steel">Free</th>
                  <th className="w-[210px] pb-3 text-meta font-normal text-steel">Premium</th>
                </tr>
              </thead>
              <tbody>
                {pricing.rows.map((row) => (
                  <tr key={row.area} className="border-b border-silver">
                    <td className="py-4 pr-6 align-top text-body text-carbon">{row.area}</td>
                    <td className="py-4 pr-6 align-top text-body text-ink">{row.free}</td>
                    <td className="py-4 align-top text-body text-ink">{row.premium}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="mt-5 max-w-[68ch] text-meta text-steel">
            Premium entitlement and displayed monthly and annual pricing are implemented;
            payment collection is not. The table describes feature-access behaviour in the
            current build rather than a live commercial subscription service.
          </p>
        </FadeInUp>
      </Section>

      {/* ── Methodology ─────────────────────────────────────────── */}
      <Section surface="linen">
        <FadeInUp className="max-w-3xl">
          <Eyebrow>Methodology</Eyebrow>
          <h2 className="mt-3 text-heading font-bold text-ink">
            Agile development, on an academic cadence
          </h2>
          <p className="mt-5 max-w-[68ch] text-body text-carbon">
            An iterative Agile approach adapted to a two-semester Final Year Project: short
            planning cycles, working software at each checkpoint, and written records
            produced as the work happens rather than reconstructed afterwards.
          </p>
        </FadeInUp>

        <div className="mt-10 border-t border-silver">
          {METHODOLOGY.map((item, i) => (
            <FadeInUp key={item.title} delay={i * 0.03}>
              <div className="grid gap-2 border-b border-silver py-6 md:grid-cols-[240px_1fr] md:gap-8">
                <h3 className="text-heading-sm font-semibold text-ink">{item.title}</h3>
                <p className="max-w-[68ch] text-body text-carbon">{item.body}</p>
              </div>
            </FadeInUp>
          ))}
        </div>
      </Section>

      {/* ── Tech stack ──────────────────────────────────────────── */}
      <Section surface="dark">
        <FadeInUp className="max-w-3xl">
          <Eyebrow tone="dark">Technology</Eyebrow>
          <h2 className="mt-3 text-heading font-bold text-white">Tech stack</h2>
          <p className="mt-5 max-w-[68ch] text-body text-silver">
            The mobile application, the administration dashboard and this project website
            are separate systems with separate stacks. All three are listed below.
          </p>
        </FadeInUp>

        <FadeInUp delay={0.06}>
          <div className="mt-10 overflow-x-auto">
            <table className="w-full min-w-[620px] border-collapse text-left">
              <thead>
                <tr className="border-b border-white/10">
                  <th className="pb-3 pr-6 text-meta font-normal text-fog">Layer</th>
                  <th className="pb-3 pr-6 text-meta font-normal text-fog">Technology</th>
                  <th className="pb-3 text-meta font-normal text-fog">Role in the project</th>
                </tr>
              </thead>
              <tbody>
                {TECH_STACK.map((row) => (
                  <tr key={row.layer} className="border-b border-white/10">
                    <td className="py-4 pr-6 align-top text-body text-silver">{row.layer}</td>
                    <td className="py-4 pr-6 align-top text-body font-medium text-white">
                      {row.choice}
                    </td>
                    <td className="py-4 align-top text-body text-silver">{row.note}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </FadeInUp>
      </Section>

      {/* ── Administration dashboard ────────────────────────────── */}
      <Section surface="dark" className="pt-0">
        <FadeInUp className="max-w-3xl">
          <Eyebrow tone="dark">Administration</Eyebrow>
          <h2 className="mt-3 text-heading font-bold text-white">
            The dashboard behind the app
          </h2>
          <p className="mt-5 max-w-[68ch] text-body text-silver">
            WiseWorkout is two applications. Alongside the Flutter mobile app, a separate
            React web dashboard gives an authorised administrator platform overview
            metrics, user browsing and account actions, business partner review, the
            exercise and official plan catalogues, challenge records and categories,
            social-post moderation, injury categories, badge definitions, broadcast
            announcements, and the platform settings — the configurable Premium prices
            and the cardio anti-cheat thresholds among them.
          </p>
        </FadeInUp>

        <FadeInUp delay={0.06} className="mt-10">
          <BrowserFrame
            src="/app/admin_dashboard.png"
            alt="WiseWorkout admin portal on the business partners screen: a table of professional applications with type, submission date, credential count and approval status, beside a detail panel showing one applicant's application, submitted credential document and review history"
          />
          <p className="mt-5 max-w-[68ch] text-meta text-fog">
            Business partner review — every professional application with the credential
            documents it submitted and the state of its approval. The accounts shown are
            internal test records created during development, and their email addresses
            have been blurred.
          </p>
        </FadeInUp>
      </Section>

      {/* ── References ──────────────────────────────────────────── */}
      <Section surface="dark" className="pt-0">
        <FadeInUp className="max-w-3xl">
          <Eyebrow tone="dark">Sources</Eyebrow>
          <h2 className="mt-3 text-heading-sm font-semibold text-white">
            References for the competitor research
          </h2>
          <ol className="mt-5 list-decimal space-y-3 pl-5 text-meta text-silver marker:text-fog">
            {REFERENCES.map((r) => (
              <li key={r} className="max-w-[80ch] leading-relaxed">
                {r}
              </li>
            ))}
          </ol>
        </FadeInUp>
      </Section>

      {/* ── Links ───────────────────────────────────────────────── */}
      <Section surface="dark" className="pt-0">
        <FadeInUp className="max-w-3xl">
          <h2 className="text-heading font-bold text-white">Project record</h2>
          <p className="mt-4 max-w-[68ch] text-body text-silver">
            Meeting minutes and reflective diaries are published weekly. Team members and
            their responsibilities are listed separately.
          </p>
          <div className="mt-7 flex flex-wrap gap-3">
            <Link
              href="/updates"
              className="inline-flex items-center justify-center rounded-full border border-white/20 px-6 py-3 text-ui font-semibold text-white transition-colors hover:border-white/40 hover:bg-white/[0.06]"
            >
              Meeting minutes and diaries →
            </Link>
            <Link
              href="/team"
              className="inline-flex items-center justify-center rounded-full border border-white/20 px-6 py-3 text-ui font-semibold text-white transition-colors hover:border-white/40 hover:bg-white/[0.06]"
            >
              Team and responsibilities →
            </Link>
          </div>
        </FadeInUp>
      </Section>
    </>
  );
}
