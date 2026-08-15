"use client";

import Image from "next/image";
import Link from "next/link";
import FadeInUp from "@/components/animations/FadeInUp";
import { StaggerChildren, StaggerItem } from "@/components/animations/StaggerChildren";
import Section from "@/components/ui/Section";
import { siteConfig } from "@/content/site-config";

/* Roles are written as what each person owns, not as a job title. */
const teamMembers = [
  {
    name: "Su Yi Maung",
    role: "Owns the schedule and the AI coaching integration",
    image: "/images/su_yi_maung.jpg",
    github: "https://github.com/Monica-Cheng",
    linkedin:
      "https://www.linkedin.com/in/monica-cheng-873512292/?skipRedirect=true",
    description:
      "Keeps the team on track while leading AI coaching integration and backend cloud functions.",
  },
  {
    name: "Meshchanov Iaroslav",
    role: "Owns user research and what the app looks like",
    image: "/images/Iarlsaov.png",
    github: "https://github.com/infamous1000",
    linkedin: "https://www.linkedin.com/in/iaroslav-meshchanov-6777a7336/",
    description:
      "Conducts user research and competitor analysis while shaping wireframes and UI prototypes.",
  },
  {
    name: "Muhammad Imran bin Nassiruddin",
    role: "Owns the data layer and wearable connections",
    image: "/images/Imran.png",
    github: "https://github.com/Imran4116",
    linkedin: "https://www.linkedin.com/in/imran-nassiruddin-337b26405/",
    description:
      "Sets up Firebase, structures Firestore, and handles wearable connection integrations.",
  },
  {
    name: "Phyu Sin Thant",
    role: "Owns the app screens and how you move between them",
    image: "/images/phyu.jpg",
    github: "https://github.com/HaTLoE",
    linkedin: "https://www.linkedin.com/in/phyusin-thant-17aab1405/",
    description:
      "Builds Flutter UI screens and implements navigation flows based on the Figma prototype.",
  },
  {
    name: "Soh Xin Yong David",
    role: "Owns security rules and the admin dashboard",
    image: "/images/david.png",
    github: "https://github.com/david37838",
    linkedin: "https://www.linkedin.com/in/david-soh-570519204/",
    description:
      "Implements Firestore security rules and supports backend logic, data handling, and the admin dashboard.",
  },
];

function GitHubIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className="h-4 w-4 fill-current">
      <path d="M12 2C6.477 2 2 6.589 2 12.248c0 4.526 2.865 8.366 6.839 9.72.5.096.682-.222.682-.493 0-.243-.009-.889-.014-1.744-2.782.617-3.369-1.372-3.369-1.372-.455-1.176-1.11-1.49-1.11-1.49-.907-.636.069-.623.069-.623 1.003.072 1.53 1.056 1.53 1.056.892 1.565 2.341 1.113 2.91.851.091-.664.349-1.113.635-1.369-2.221-.258-4.556-1.139-4.556-5.07 0-1.12.389-2.036 1.028-2.754-.103-.259-.446-1.301.098-2.712 0 0 .839-.275 2.75 1.052A9.347 9.347 0 0 1 12 6.836c.85.004 1.706.117 2.505.344 1.91-1.327 2.748-1.052 2.748-1.052.546 1.411.203 2.453.1 2.712.64.718 1.026 1.634 1.026 2.754 0 3.941-2.339 4.809-4.566 5.063.359.319.679.95.679 1.915 0 1.382-.012 2.496-.012 2.835 0 .274.18.594.688.492C19.137 20.61 22 16.772 22 12.248 22 6.589 17.523 2 12 2Z" />
    </svg>
  );
}

function LinkedInIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className="h-4 w-4 fill-current">
      <path d="M6.94 8.5H3.56V20h3.38V8.5ZM5.25 3C4.17 3 3.3 3.89 3.3 4.98c0 1.08.86 1.97 1.93 1.97h.02c1.1 0 1.98-.89 1.98-1.97C7.21 3.89 6.35 3 5.25 3ZM20.7 12.8c0-3.53-1.88-5.17-4.39-5.17-2.02 0-2.92 1.13-3.43 1.93V8.5H9.5c.04.7 0 11.5 0 11.5h3.38v-6.42c0-.34.02-.68.13-.92.27-.69.88-1.4 1.91-1.4 1.35 0 1.89 1.05 1.89 2.59V20h3.38v-7.2Z" />
    </svg>
  );
}

function SocialLink({
  href,
  label,
  children,
}: {
  href: string;
  label: string;
  children: React.ReactNode;
}) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noreferrer"
      aria-label={label}
      className="inline-flex h-9 w-9 items-center justify-center rounded-full border border-silver text-steel transition-colors hover:border-ink hover:text-ink"
    >
      {children}
    </a>
  );
}

function TeamMemberCard({ member }: { member: (typeof teamMembers)[number] }) {
  return (
    <article className="flex h-full flex-col rounded-card border border-silver bg-white p-5 shadow-whisper">
      <div className="relative aspect-[4/4.6] overflow-hidden rounded-xl bg-linen">
        <Image
          src={member.image}
          alt={member.name}
          fill
          className="object-cover"
          sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 25vw"
        />
      </div>

      <div className="mt-5 flex flex-1 flex-col">
        <h2 className="text-heading-sm font-semibold text-ink">{member.name}</h2>
        <p className="mt-1 text-meta text-steel">{member.role}</p>
        <p className="mt-3 flex-1 text-lede text-carbon">{member.description}</p>
      </div>

      <div className="mt-5 flex items-center gap-3">
        <SocialLink href={member.github} label={`${member.name} on GitHub`}>
          <GitHubIcon />
        </SocialLink>
        <SocialLink href={member.linkedin} label={`${member.name} on LinkedIn`}>
          <LinkedInIcon />
        </SocialLink>
      </div>
    </article>
  );
}

export default function TeamPageClient() {
  const { academic } = siteConfig;

  return (
    <>
      <Section surface="light" className="pb-8 pt-14">
        <FadeInUp className="max-w-3xl">
          <p className="text-meta text-steel">
            {academic.group} · {academic.course} · {academic.school}
          </p>
          <h1 className="mt-4 text-display font-bold text-ink">
            Five people build this. Here is who owns what.
          </h1>
          <p className="mt-5 max-w-[62ch] text-lede text-carbon">
            No agency, no outsourcing. Every screen, query and security rule in
            WiseWorkout was written by one of the five below.
          </p>
        </FadeInUp>
      </Section>

      <Section surface="light" className="pt-8">
        <StaggerChildren className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-6">
          {teamMembers.map((member, i) => (
            <StaggerItem
              key={member.name}
              className={[
                "lg:col-span-2",
                i === 3 ? "lg:col-start-2" : "",
                i === 4 ? "lg:col-start-4" : "",
              ]
                .filter(Boolean)
                .join(" ")}
            >
              <TeamMemberCard member={member} />
            </StaggerItem>
          ))}
        </StaggerChildren>
      </Section>

      <Section surface="dark">
        <FadeInUp className="max-w-3xl">
          <h2 className="text-display font-bold text-white">
            Every week, each of us writes down what we got wrong.
          </h2>
          <p className="mt-5 max-w-[62ch] text-lede text-silver">
            Meeting minutes and individual reflective diaries are published on this
            site as they are written.
          </p>
          <Link
            href="/updates"
            className="mt-8 inline-flex items-center justify-center rounded-full border border-white/20 px-6 py-3 text-ui font-semibold text-white transition-colors hover:border-white/40 hover:bg-white/[0.06]"
          >
            Read the updates →
          </Link>
        </FadeInUp>
      </Section>
    </>
  );
}
