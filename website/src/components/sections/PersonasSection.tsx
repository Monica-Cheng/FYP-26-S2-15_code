import Section, { Eyebrow } from "@/components/ui/Section";
import FadeInUp from "@/components/animations/FadeInUp";
import { siteConfig } from "@/content/site-config";

/**
 * The strongest argument the product has: it bends to the person, not the other
 * way round. A hairline grid rather than six tinted icon cards — the point is
 * the breadth of the list, so nothing should compete with the words.
 */
export default function PersonasSection() {
  const { personas } = siteConfig;

  return (
    <Section surface="light">
      <FadeInUp className="mx-auto max-w-3xl text-center">
        <Eyebrow>{personas.eyebrow}</Eyebrow>
        <h2 className="mt-3 text-heading font-bold text-ink">{personas.heading}</h2>
        <p className="mx-auto mt-4 max-w-[58ch] text-lede text-carbon">{personas.lede}</p>
      </FadeInUp>

      <FadeInUp delay={0.06}>
        <div className="mt-12 grid gap-px overflow-hidden rounded-card border border-silver bg-silver sm:grid-cols-2 lg:grid-cols-3">
          {personas.items.map((item) => (
            <div key={item.label} className="bg-canvas px-6 py-7">
              <h3 className="text-heading-sm font-semibold text-ink">{item.label}</h3>
              <p className="mt-2 text-lede text-carbon">{item.body}</p>
            </div>
          ))}
        </div>
      </FadeInUp>
    </Section>
  );
}
