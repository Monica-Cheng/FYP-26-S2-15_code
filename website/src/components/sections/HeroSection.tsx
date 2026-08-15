"use client";

import { motion, useReducedMotion } from "framer-motion";
import { siteConfig } from "@/content/site-config";
import { buttonClass } from "@/components/ui/Button";
import DownloadCta from "@/components/ui/DownloadCta";
import HashLink from "@/components/ui/HashLink";
import NotificationCard from "@/components/ui/NotificationCard";
import PhoneFrame from "@/components/ui/PhoneFrame";

/* Absolute placements for the four cards at lg+, inside an 880px orbit box so
   they stay near the device instead of drifting to the page edges. Below lg
   they stack into a plain grid. */
const placements = [
  "left-0 top-10 w-[236px]",
  "right-0 top-2 w-[240px]",
  "left-6 bottom-12 w-[216px]",
  "right-2 bottom-6 w-[244px]",
];

export default function HeroSection() {
  const reduce = useReducedMotion();
  const { hero, notifications, ctaNote } = siteConfig;

  return (
    <section className="bg-canvas px-6 pb-20 pt-10 md:pb-24 md:pt-14">
      <div className="mx-auto w-full max-w-[1200px]">
        <div className="mx-auto max-w-3xl text-center">
          <p className="text-meta text-steel">{hero.eyebrow}</p>

          <h1 className="mx-auto mt-5 max-w-[20ch] text-display font-bold text-ink">
            {hero.headline}
          </h1>

          <p className="mx-auto mt-6 max-w-[58ch] text-lede text-carbon">{hero.subhead}</p>

          <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
            <DownloadCta />
            <HashLink href={hero.secondaryHref} className={buttonClass("ghost")}>
              {hero.secondaryCta}
            </HashLink>
          </div>

          <p className="mt-4 text-meta text-steel">{ctaNote}</p>
        </div>

        {/* Signature: four cards orbiting the real app screen. Spent here only. */}
        <div className="relative mx-auto mt-14 flex max-w-[880px] justify-center lg:mt-16 lg:min-h-[620px] lg:items-center">
          <motion.div
            animate={reduce ? undefined : { y: [0, -10, 0] }}
            transition={{ repeat: Infinity, duration: 5, ease: "easeInOut" }}
          >
            <PhoneFrame
              src="/app/main.png"
              alt="WiseWorkout home screen: a 17-day streak, today's calories and macros, and the day's plan"
              width={268}
              priority
            />
          </motion.div>

          {notifications.map((note, i) => (
            <motion.div
              key={note.title}
              className={`absolute hidden lg:block ${placements[i]}`}
              style={{ rotate: `${note.rotate}deg` }}
              initial={reduce ? undefined : { opacity: 0, y: 14 }}
              animate={reduce ? undefined : { opacity: 1, y: 0 }}
              transition={{ delay: 0.25 + i * 0.12, duration: 0.5, ease: [0.22, 1, 0.36, 1] }}
            >
              <NotificationCard title={note.title} meta={note.meta} accent={note.accent} />
            </motion.div>
          ))}
        </div>

        <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:hidden">
          {notifications.map((note) => (
            <NotificationCard
              key={note.title}
              title={note.title}
              meta={note.meta}
              accent={note.accent}
            />
          ))}
        </div>
      </div>
    </section>
  );
}
