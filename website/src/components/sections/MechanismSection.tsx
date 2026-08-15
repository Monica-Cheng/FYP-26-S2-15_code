import Section, { Eyebrow } from "@/components/ui/Section";
import FadeInUp from "@/components/animations/FadeInUp";
import { StaggerChildren, StaggerItem } from "@/components/animations/StaggerChildren";
import PhoneFrame from "@/components/ui/PhoneFrame";
import { siteConfig } from "@/content/site-config";

/* Question → question → result. Real onboarding screens, in the order you meet them. */
const shots = [
  {
    src: "/app/schedule.png",
    alt: "Setup question asking how many days per week you can train, from 2 to 6",
  },
  {
    src: "/app/equipment.png",
    alt: "Setup question asking what equipment you have: home bodyweight, gym with weights, outdoor or both",
  },
  {
    src: "/app/library_plans.png",
    alt: "My Plans Library showing combined, cardio, custom and gym plans ready to follow",
  },
];

export default function MechanismSection() {
  const { mechanism } = siteConfig;

  return (
    <Section id="how-it-works" surface="linen">
      <FadeInUp className="mx-auto max-w-3xl text-center">
        <Eyebrow>{mechanism.eyebrow}</Eyebrow>
        <h2 className="mt-3 text-heading font-bold text-ink">{mechanism.heading}</h2>
        <p className="mx-auto mt-4 max-w-[58ch] text-lede text-carbon">{mechanism.lede}</p>
      </FadeInUp>

      <StaggerChildren className="mt-14 grid gap-12 md:grid-cols-3 md:gap-8">
        {mechanism.steps.map((step, i) => (
          <StaggerItem key={step.number}>
            <div className="flex flex-col items-center text-center md:items-start md:text-left">
              <PhoneFrame src={shots[i].src} alt={shots[i].alt} width={190} />

              <span className="mt-8 inline-flex rounded-full border border-silver px-3 py-1 text-meta font-semibold text-steel">
                {step.number}
              </span>
              <h3 className="mt-4 text-heading-sm font-semibold text-ink">{step.title}</h3>
              <p className="mt-2 text-lede text-carbon">{step.body}</p>
            </div>
          </StaggerItem>
        ))}
      </StaggerChildren>
    </Section>
  );
}
