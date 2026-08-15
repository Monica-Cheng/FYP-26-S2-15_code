export const siteConfig = {
  name: "WiseWorkout",
  tagline: "Fitness that fits your life",
  description:
    "Track workouts, runs, rides and calories, follow a plan built around your schedule, join challenges and find a coach — all in one app. A Final Year Project by FYP26S215 at SIM–University of Wollongong.",

  academic: {
    group: "FYP26S215",
    course: "CSIT321",
    school: "SIM–University of Wollongong",
    year: "2025/26",
  },

  navLinks: [
    { label: "Features", href: "/#features" },
    { label: "How it works", href: "/#how-it-works" },
    { label: "Team", href: "/team" },
    { label: "Updates", href: "/updates" },
    { label: "About", href: "/about" },
  ],

  /* One conversion verb. Same words on every amber button. It was "Get early
     access" while the app was unreleased and the button opened a waitlist form;
     there is now a real build to install, so the verb is the install. The note
     goes under every instance — this is an APK from Google Drive, not a Play
     Store listing, and people should know that before they tap. */
  cta: "Download now",
  ctaHref:
    "https://drive.google.com/file/d/15dFHyanQP7_2fPG0UaN9xxHfIJ5WxknD/view?usp=sharing",
  ctaNote: "APK for Android, hosted on Google Drive.",

  announcement: {
    text: "The Android build is ready",
    linkLabel: "Download the APK",
  },

  hero: {
    eyebrow: "Gym, running, cycling and food — in one app",
    headline: "Fitness that fits your life.",
    subhead:
      "Track workouts, runs, rides and calories. Follow a plan built around the days and hours you actually have. Join challenges, find a coach, and train alongside people going the same way.",
    secondaryCta: "See how it works",
    secondaryHref: "/#how-it-works",
  },

  /* Signature element: cards orbiting the hero phone. Every value here is real —
     it appears on a screen in /public/app. */
  notifications: [
    {
      title: "Today's plan is ready",
      meta: "Push + Cardio Finisher · 31 min",
      accent: "blue" as const,
      rotate: -3,
    },
    {
      title: "1,320 kcal in · 90g protein",
      meta: "Counted against what you trained",
      accent: "none" as const,
      rotate: 2,
    },
    {
      title: "17-day streak",
      meta: "Your longest yet",
      accent: "amber" as const,
      rotate: 3,
    },
    {
      title: "Challenge joined",
      meta: "100 cal target · 6 people in",
      accent: "none" as const,
      rotate: -2,
    },
  ],

  problem: {
    heading: "Right now, this takes four apps.",
    lede: "One for lifting. One for runs. One for food. And a group chat where you try to stay accountable. None of them know what the others know.",
    items: [
      {
        label: "Scattered",
        title: "Your week never adds up to one picture.",
        body: "The run is in one app, the sets in another, dinner in a third. Nothing tells you how the whole week actually went.",
      },
      {
        label: "One-size plans",
        title: "Most plans assume you have an hour, five days a week.",
        body: "You don't. So you start, miss two sessions, and stop — not because you lack discipline, but because the plan never matched your week.",
      },
      {
        label: "On your own",
        title: "Week three is where most people quit.",
        body: "Nothing is watching, nobody notices, and skipping a session costs you nothing at all.",
      },
    ],
  },

  mechanism: {
    eyebrow: "Plan Match",
    heading: "Six questions. Then a plan that fits.",
    lede: "No spreadsheets and no guesswork. WiseWorkout builds around the time, equipment and experience you actually have.",
    steps: [
      {
        number: "01",
        title: "Tell it about your week",
        body: "How many days you can train — 2 to 6 — and how long a session realistically runs: 30, 45, 60 or 75+ minutes. Pick what's true, not what's ideal.",
      },
      {
        number: "02",
        title: "Tell it what you've got",
        body: "Gym, cardio, or both. Home bodyweight, a full gym, or outdoors. It only programmes what you can actually get your hands on.",
      },
      {
        number: "03",
        title: "Get your plan",
        body: "Beginner, intermediate or advanced — calibrated to match. Connect Apple Health and your steps, heart rate, sleep and workouts sync in on their own.",
      },
    ],
  },

  /* USP 1 in the project documentation. Five named mechanisms — this is the
     evidence behind "fits your life", not a slogan. */
  adaptive: {
    eyebrow: "When life gets in the way",
    heading: "Built for the weeks that don't go to plan.",
    lede: "Most plans assume nothing interrupts them. These five exist because something always does.",
    items: [
      {
        name: "Compress Workout",
        body: "Short on time? Shorten the session you already had scheduled instead of skipping it.",
      },
      {
        name: "Missed Workout Check-in",
        body: "Miss one and the app records it, acknowledges it, and moves on. No silent guilt-tripping.",
      },
      {
        name: "Break Mode",
        body: "Going away, ill, or just need to stop? Pause reminders and missed-session tracking for as many days as you choose.",
      },
      {
        name: "Resume",
        body: "Walk out mid-workout and the tracked session is still there, saved where you left it.",
      },
      {
        name: "Injury-aware filtering",
        body: "Record your injury areas and WiseWorkout avoids or flags exercises that involve them.",
      },
    ],

    /* The one mechanism in the list that is easier shown than described — three
       real screens, in the order you meet them. Captions are index-matched to
       the shots in AdaptiveSection. */
    injury: {
      title: "What injury-aware filtering actually looks like",
      body: "You record the area once. From then on it travels with you into every session the app can check.",
      captions: [
        "Log the area and how bad it is. The filtering itself is a switch you control.",
        "Before the session starts, anything that touches it is flagged. Keep it or drop it — the call stays yours.",
        "Outdoor cardio opens with the same reminder rather than a silent block.",
      ],
      note: "Guidance, not medical advice — the app says so on the screen where you record the injury.",
    },
  },

  featuresIntro: {
    eyebrow: "Features",
    heading: "Five things it does. All on the same screen.",
  },

  features: [
    {
      eyebrow: "Food",
      title: "Three ways to log a meal.",
      hook: "Describe it in words, photograph it, or scan the barcode.",
      explanation:
        "Type what you ate and WiseWorkout works out the calories and macros. Point the camera at the plate, or scan a packet — photo and barcode capture are Premium. What comes back is labelled an estimate, with the assumption it made written underneath, and it lands on the same screen as your training with protein, carbs and fat broken out.",
      outcome: "One glance tells you where the day stands.",
      screens: [
        {
          src: "/app/food_scan.png",
          alt: "Log a Meal screen with Scan, Barcode and Describe tabs, camera pointed at a plate of rice, egg, pork and greens",
        },
        {
          src: "/app/food_result.png",
          alt: "Estimated result for the photographed meal: 700 calories with 30g protein, 90g carbs and 25g fat, marked as an estimate",
        },
      ],
    },
    {
      eyebrow: "Plans",
      title: "A workout that fits the time you have.",
      hook: "Filter by level, goal and sport — then follow it day by day.",
      explanation:
        "Gym splits, cardio blocks, or combined programmes that pair real strength work with a cardio finisher. Take one from the library or build your own custom routine and keep it alongside the rest.",
      outcome: "Twenty minutes or a full hour — there's something for the week you're actually having.",
      screens: [
        {
          src: "/app/plans.png",
          alt: "Explore Plans screen with level, goal and sport filters, featured plans, and separate gym and cardio plan lists",
        },
      ],
    },
    {
      eyebrow: "WiseCoach",
      title: "It explains your session before you ask.",
      hook: "Every finished workout gets a short recap in plain language, automatically.",
      explanation:
        "Finish a gym, cardio or combined session and the recap is waiting on the session itself, next to the numbers it is describing. Where there is history to draw on it adds the context — recent comparable sessions, how the week is tracking against your plan, where the streak stands. Separately you can ask WiseCoach anything: what to do on leg day, how to work around an injury, why last month stalled. It reads your training history, current plan and injury profile before replying. General guidance, not medical advice.",
      outcome: "You get the meaning, not another chart to interpret.",
      screens: [
        {
          src: "/app/ai.png",
          alt: "WiseCoach chat screen showing it uses training history, current plan and injury profile, with a Find Professional button",
        },
        {
          src: "/app/session_recap.png",
          alt: "A finished night cycling session showing duration, distance, pace, calories and elevation, a WiseCoach summary of the session, XP earned and the route map",
        },
      ],
    },
    {
      eyebrow: "Club",
      title: "Don't train alone.",
      hook: "Friends, challenges, a weekly XP leaderboard — and none of it compulsory.",
      explanation:
        "Join a public challenge or set up a private one with friends. Follow people, react and comment on workout and nutrition posts, and see where you land on the weekly XP board. Train entirely on your own if you prefer — planning, tracking and coaching never depend on any of it.",
      outcome: "The weeks you don't feel like training are the weeks this earns its place.",
      screens: [
        {
          src: "/app/chellenges.png",
          alt: "Club screen with Leaderboard, Challenges and Feed tabs, showing public challenges you can join",
        },
      ],
    },
    {
      eyebrow: "Progress",
      title: "See whether any of it is working.",
      hook: "Calories burned, gym volume, pace and distance — by week, month or year.",
      explanation:
        "Every session lands in your charts and activity history, tagged gym, cardio, manual or custom. You earn XP for what you finish and level up as the weeks stack, so the boring middle of a training block still shows movement.",
      outcome: "Proof that the last three months went somewhere.",
      screens: [
        {
          src: "/app/progress.png",
          alt: "Progress screen showing weekly calories burned and gym training charts with week, month and year views",
        },
      ],
    },
  ],

  personas: {
    eyebrow: "Built for real weeks",
    heading: "Your goals. Your schedule. Your way.",
    lede: "There is no one-size-fits-all plan. WiseWorkout adapts to the person actually using it.",
    items: [
      { label: "Only 20 minutes", body: "Short, focused sessions that still count." },
      { label: "Three days a week", body: "A plan built for the days you really have." },
      { label: "Training for a race", body: "Every run, pace and kilometre tracked." },
      { label: "Out on the bike", body: "Log rides and watch the distance stack up." },
      { label: "Trying to lose weight", body: "Meals, macros and activity in one place." },
      { label: "Starting from zero", body: "Beginner plans, and a coach to ask when you're stuck." },
    ],
  },

  /* Named competitors and their strengths come from the project's own competitor
     research (Freeletics, Fitbod, Strava, Hevy, MyFitnessPal). The honest finding
     is that none of these capabilities is unique in isolation — the integration is. */
  comparison: {
    heading: "Every one of these does its job well.",
    lede: "We looked hard at the apps people already use. Taken one at a time, nothing WiseWorkout does is unheard of. The difference is that here it is all one workflow instead of five.",
    rows: [
      {
        name: "Freeletics",
        credit: "Adapts sessions on the fly and personalises training with AI.",
        gap: "Built around its own bodyweight-first programming. Your gym log, runs and food live elsewhere.",
      },
      {
        name: "Fitbod",
        credit: "Excellent at personalising strength workouts session to session.",
        gap: "Strength is the whole product. Cardio, nutrition and any social accountability are somebody else's problem.",
      },
      {
        name: "Strava",
        credit: "The best social layer in fitness, plus AI summaries of your activities.",
        gap: "Runs and rides are first-class; structured gym programming and calorie tracking are not.",
      },
      {
        name: "Hevy",
        credit: "Clean gym logging with solid progress charts and a social side.",
        gap: "It records what you did. It does not reshape the week when you miss two sessions.",
      },
      {
        name: "MyFitnessPal",
        credit: "Camera and barcode food logging against a database twenty years deep.",
        gap: "Knows what went in, guesses what went out. Your training is data it never sees.",
      },
    ],
    close:
      "WiseWorkout puts planning, adaptive support, gym and cardio tracking, nutrition, AI interpretation, social accountability and access to real coaches in one place — and lets each one inform the next.",
  },

  stats: {
    heading: "What a tracked block looks like",
    lede: "These four numbers come from one test account over a twelve-week block during internal development. They are a sample of the readout you get — not user traction. WiseWorkout has not launched and has no users yet.",
    items: [
      { value: "47", label: "Sessions tracked" },
      { value: "38.2km", label: "Distance covered" },
      { value: "7", label: "Day streak record" },
      { value: "1,240kg", label: "Volume lifted" },
    ],
  },

  /* Free/Premium reflects the implemented entitlement model. Payment collection is
     NOT built — the in-app Upgrade action reads "Coming Soon". Do not imply otherwise.
     TODO: 29 SGD is a placeholder supplied by the team; replace with the real
     configured monthly price, and add the annual price once it is decided. */
  pricing: {
    eyebrow: "Free and Premium",
    heading: "Free does the training. Premium lifts three limits.",
    lede: "Basic training is not behind a paywall. Free users get planning, tracking, adaptive support, progress, nutrition, social features and coaching — the whole core product.",
    price: "SGD 29",
    priceSuffix: "/ month",
    priceNote:
      "Payment is not switched on yet. In the current build the Upgrade button reads Coming Soon, and everything is free.",
    rows: [
      { area: "Plans, tracking, progress and social", free: "Included", premium: "Included" },
      { area: "Compress, Missed Check-in, Break Mode, injury filtering", free: "Included", premium: "Included" },
      { area: "Post-session WiseCoach recap", free: "Included", premium: "Included" },
      { area: "WiseCoach typed chat", free: "25 messages a month", premium: "No cap" },
      { area: "Describe a Meal", free: "Included", premium: "Included" },
      { area: "Photo and barcode food scanning", free: "Locked", premium: "Included" },
      { area: "Private challenges you create", free: "Up to 3", premium: "No cap" },
    ],
  },

  coaches: {
    eyebrow: "For fitness professionals",
    heading: "Coach on WiseWorkout.",
    lede: "Get verified, appear in Find a Professional, and take on clients who are already tracking their training.",
    items: [
      {
        title: "Apply and get verified",
        body: "Submit your credentials. An administrator reviews every application before a profile goes live.",
      },
      {
        title: "Receive requests",
        body: "Approved professionals appear in Find a Professional. Users send coaching requests; you accept or decline.",
      },
      {
        title: "Publish your own plans",
        body: "Write workout plans under your name and make them visible to the clients you have accepted.",
      },
    ],
    /* Both ends of the same route: what a professional fills in, and what a user
       sees once it has been approved. Captions are index-matched to the shots in
       CoachesSection. */
    shots: [
      {
        caption:
          "The application. Coach type, experience, a bio — and at least one certificate, licence or proof of qualification, which is not optional.",
      },
      {
        caption:
          "What users see afterwards: approved professionals only, filtered by trainer, running coach, physiotherapist or nutritionist.",
      },
    ],
    note: "Professional accounts are applied for inside the app and reviewed before they appear. The profiles above are internal test accounts from development.",
  },

  offer: {
    heading: "What you get for installing it early",
    lede: "WiseWorkout is a Final Year Project, not a company. There's no plan to buy and no upsell waiting at the end. This is the whole of it.",
    items: [
      {
        title: "The build itself",
        body: "The APK for Android, downloaded straight from us. No store listing, no launch queue, no review gate between the build and your phone.",
      },
      {
        title: "A direct line to the five people who built it",
        body: "Not a support form. The names and roles are on the team page, and the replies come from them.",
      },
      {
        title: "Your feedback answered in writing",
        body: "Every report gets a written response — what we're changing, or why we're not.",
      },
      {
        title: "Your feedback in the published record",
        body: "Reports that change the build appear in that week's meeting minute on this site, credited by name if you want it.",
      },
    ],
    riskReversal:
      "No card, no ads, and no sale of training data. Leave whenever and export everything you logged as CSV.",
  },

  builtInPublic: {
    heading: "Every meeting we've had is on this website.",
    lede: "Most products show you the finished thing. The full record of this one is public — and it's public because it's graded.",
    items: [
      {
        title: "Weekly meeting minutes",
        body: "Date, attendees, agenda, key decisions and action items. Written for our supervisor, published unedited.",
        href: "/updates",
        linkLabel: "Read the minutes",
      },
      {
        title: "Individual reflective diaries",
        body: "Each of the five of us writes weekly about what shipped, what broke, and what we got wrong.",
        href: "/updates",
        linkLabel: "Read the diaries",
      },
      {
        title: "The team, by name",
        body: "Five students at SIM–University of Wollongong. Roles are written as what each person owns, not as job titles.",
        href: "/team",
        linkLabel: "Meet the team",
      },
    ],
  },

  faq: {
    heading: "The questions we actually get",
    items: [
      {
        question: "How do I install it?",
        answer:
          "Download the APK from any of the buttons on this page and open it on an Android phone. Android asks once for permission to install an app from outside the Play Store — that prompt is normal for an app handed out this way.",
      },
      {
        question: "Is this just another workout tracker?",
        answer:
          "It's the four apps you're already using, in one. Workouts, runs and rides, calories and macros, and the people you train with all sit on the same screen — which means the plan it gives you can account for the whole week instead of one slice of it.",
      },
      {
        question: "I don't have an hour a day.",
        answer:
          "That's the point. Setup asks how long your sessions realistically run — 30, 45, 60 or 75+ minutes — and how many days a week you can train, anywhere from 2 to 6. It programmes for that, not for an ideal week you don't have. The app's own words: shorter and focused often beats long and inconsistent.",
      },
      {
        question: "Is this just ChatGPT with a logo?",
        answer:
          "No, and the difference is what it can see. A chat window starts empty every time — you'd have to retype your last month of sets, your current plan and your injury history before it could say anything useful. WiseCoach already has all three and says so at the top of the thread. It also writes a recap after every session without being asked, which a chat window cannot do at all. There is a language model writing the sentence; what makes the answer worth anything is the training data behind it. And when you want a person instead of a model, Find Professional is one tap away.",
      },
      {
        question: "I already use a running app. Do I have to give it up?",
        answer:
          "No. Connect Apple Health and your workouts, steps, heart rate and sleep sync in automatically, so runs you record elsewhere still count toward your week here. Plenty of people run both for a while.",
      },
      {
        question: "I'm a complete beginner.",
        answer:
          "Pick Beginner at setup and the whole plan calibrates down to match. There are beginner plans in the library, WiseCoach answers the questions you'd rather not ask a stranger at the gym, and if you want a real person, you can search for one in the app.",
      },
      {
        question: "What does it cost?",
        answer:
          "Nothing, right now. Beyond that there are two tiers: Free keeps the whole core product — planning, tracking, adaptive support, progress, nutrition, social and coaching — while Premium removes the 25-message monthly cap on WiseCoach chat, unlocks photo and barcode food scanning, and lifts the three-challenge limit. Premium is SGD 29 a month, but payment is not connected yet: in the current build the Upgrade button reads Coming Soon.",
      },
      {
        question: "Do I need Premium to get anything useful?",
        answer:
          "No, and that was deliberate. Plans, Plan Match, gym and cardio tracking, Compress, Break Mode, injury filtering, progress analytics, the post-session recap, friends, challenges and Find a Professional are all on the Free tier. Premium lifts three specific limits rather than gating the training itself.",
      },
    ],
  },

  finalCta: {
    heading: "Your fitness. Your way.",
    lede: "Start building a routine that fits the week you're actually having — not the one a plan assumes you have.",
    riskReversal: "No card, no ads, and no sale of training data.",
    /* The one remaining way into the mailing list now that the conversion is a
       download. */
    waitlistPrompt: "Want to know when the next build lands?",
    waitlistLink: "Join the mailing list",
  },

  waitlist: {
    heading: "Hear about the next build",
    lede: "The Android build is already up there. Leave an email and we'll write once, when there's a new one worth installing.",
    inputLabel: "Email",
    placeholder: "you@example.com",
    submit: "Join the list",
    submitting: "Sending…",
    successTitle: "You're on the list.",
    successBody: "We'll email you when the next build is ready. Nothing else.",
    duplicate: "That address is already on the list. You're set.",
    error: "Something went wrong. Try again in a moment.",
    riskReversal: "No card. No ads. Unsubscribe in one click.",
  },

  footer: {
    blurb:
      "One app for workouts, runs, rides, food and the people you train with — built around your goals and your schedule. A Final Year Project at SIM–University of Wollongong.",
    groups: [
      {
        title: "Product",
        links: [
          { label: "Features", href: "/#features" },
          { label: "How it works", href: "/#how-it-works" },
          { label: "Comparison", href: "/#comparison" },
          { label: "Pricing", href: "/#pricing" },
          { label: "FAQ", href: "/#faq" },
        ],
      },
      {
        title: "Project",
        links: [
          { label: "About", href: "/about" },
          { label: "Team", href: "/team" },
          { label: "Updates", href: "/updates" },
        ],
      },
    ],
  },
};
