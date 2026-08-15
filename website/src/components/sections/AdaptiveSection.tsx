import Section, { Eyebrow } from "@/components/ui/Section";
import FadeInUp from "@/components/animations/FadeInUp";
import { StaggerChildren, StaggerItem } from "@/components/animations/StaggerChildren";
import PhoneFrame from "@/components/ui/PhoneFrame";
import { siteConfig } from "@/content/site-config";

/* Record it → get warned before the session → get warned again outdoors.
   Index-matched to siteConfig.adaptive.injury.captions. */
const injuryShots = [
  {
    src: "/app/injury_profile.png",
    alt: "Health Profile screen with injury filtering switched on, a severe left ankle and a moderate right knee recorded, and a notice that this is not a substitute for medical advice",
  },
  {
    src: "/app/injury_review.png",
    alt: "Injury Review sheet shown before a workout starts, listing Barbell Row and Cable Row as exercises that may affect the lower back, each with Keep and Remove buttons",
  },
  {
    src: "/app/injury_alert.png",
    alt: "Outdoor cardio tracking screen opening with an injury alert that lists the user's active injuries",
  },
];

/**
 * The five named mechanisms behind "fits your life". Without these the promise is
 * a slogan; with them it is a feature list the reader can hold the product to.
 * Numbered hairline rows — the point is that there are five, so nothing should
 * compete with the names. The fifth one then gets shown, because "injury-aware"
 * is the claim in the list that sounds the most like marketing.
 */
export default function AdaptiveSection() {
  const { adaptive } = siteConfig;

  return (
    <Section surface="light">
      <FadeInUp className="mx-auto max-w-3xl text-center">
        <Eyebrow>{adaptive.eyebrow}</Eyebrow>
        <h2 className="mt-3 text-heading font-bold text-ink">{adaptive.heading}</h2>
        <p className="mx-auto mt-4 max-w-[58ch] text-lede text-carbon">{adaptive.lede}</p>
      </FadeInUp>

      <div className="mt-12 border-t border-silver">
        {adaptive.items.map((item, i) => (
          <FadeInUp key={item.name} delay={i * 0.04}>
            <div className="grid gap-2 border-b border-silver py-6 md:grid-cols-[56px_240px_1fr] md:items-baseline md:gap-6">
              <p className="text-meta text-steel">{String(i + 1).padStart(2, "0")}</p>
              <h3 className="text-heading-sm font-semibold text-ink">{item.name}</h3>
              <p className="max-w-[62ch] text-lede text-carbon">{item.body}</p>
            </div>
          </FadeInUp>
        ))}
      </div>

      <FadeInUp className="mx-auto mt-16 max-w-3xl text-center">
        <h3 className="text-heading-sm font-semibold text-ink">{adaptive.injury.title}</h3>
        <p className="mx-auto mt-3 max-w-[58ch] text-lede text-carbon">
          {adaptive.injury.body}
        </p>
      </FadeInUp>

      <StaggerChildren className="mt-12 grid gap-12 md:grid-cols-3 md:gap-8">
        {adaptive.injury.captions.map((caption, i) => (
          <StaggerItem key={injuryShots[i].src}>
            <div className="flex flex-col items-center text-center md:items-start md:text-left">
              <PhoneFrame src={injuryShots[i].src} alt={injuryShots[i].alt} width={190} />
              <p className="mt-8 max-w-[38ch] text-lede text-carbon">{caption}</p>
            </div>
          </StaggerItem>
        ))}
      </StaggerChildren>

      <FadeInUp delay={0.15}>
        <p className="mt-10 text-meta text-steel">{adaptive.injury.note}</p>
      </FadeInUp>
    </Section>
  );
}
