import Section, { Eyebrow } from "@/components/ui/Section";
import FadeInUp from "@/components/animations/FadeInUp";
import PhoneFrame from "@/components/ui/PhoneFrame";
import { siteConfig } from "@/content/site-config";

/* The application, then the listing it produces once an administrator approves it.
   Index-matched to siteConfig.coaches.shots. */
const shots = [
  {
    src: "/app/partner_application.png",
    alt: "Register as Professional form asking for name, coach type — trainer, running coach, physiotherapist or nutritionist — experience, bio, and at least one credential document",
  },
  {
    src: "/app/find_professional.png",
    alt: "Find a Professional list showing verified professionals with their type, bio and credentials, each with buttons to request them as a coach or contact them",
  },
];

/**
 * The product's second audience. Everything here is applied for and reviewed
 * inside the app, so there is no call to action on the website — stating the
 * route honestly is the whole job of this section.
 */
export default function CoachesSection() {
  const { coaches } = siteConfig;

  return (
    <Section surface="linen">
      <FadeInUp className="mx-auto max-w-3xl text-center">
        <Eyebrow>{coaches.eyebrow}</Eyebrow>
        <h2 className="mt-3 text-heading font-bold text-ink">{coaches.heading}</h2>
        <p className="mx-auto mt-4 max-w-[58ch] text-lede text-carbon">{coaches.lede}</p>
      </FadeInUp>

      <div className="mt-12 grid gap-8 md:grid-cols-3 md:gap-10">
        {coaches.items.map((item, i) => (
          <FadeInUp key={item.title} delay={i * 0.05}>
            <span className="inline-flex rounded-full border border-silver px-3 py-1 text-meta font-semibold text-steel">
              {String(i + 1).padStart(2, "0")}
            </span>
            <h3 className="mt-4 text-heading-sm font-semibold text-ink">{item.title}</h3>
            <p className="mt-2 text-lede text-carbon">{item.body}</p>
          </FadeInUp>
        ))}
      </div>

      <div className="mx-auto mt-16 grid max-w-4xl gap-12 sm:grid-cols-2 sm:gap-10">
        {coaches.shots.map((shot, i) => (
          <FadeInUp key={shots[i].src} delay={i * 0.05}>
            <div className="flex flex-col items-center text-center">
              <PhoneFrame src={shots[i].src} alt={shots[i].alt} width={220} />
              <p className="mt-8 max-w-[42ch] text-lede text-carbon">{shot.caption}</p>
            </div>
          </FadeInUp>
        ))}
      </div>

      <FadeInUp delay={0.15}>
        <p className="mt-12 text-meta text-steel">{coaches.note}</p>
      </FadeInUp>
    </Section>
  );
}
