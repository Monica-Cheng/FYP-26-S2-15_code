import Section from "@/components/ui/Section";
import FadeInUp from "@/components/animations/FadeInUp";
import { siteConfig } from "@/content/site-config";

/**
 * Departure-board list, not three icon cards. Rows share one hairline grid so
 * the eye reads down a single column of type rather than across three tiles.
 */
export default function ProblemSection() {
  const { problem } = siteConfig;

  return (
    <Section id="problem" surface="light">
      <FadeInUp className="mx-auto max-w-3xl text-center">
        <h2 className="text-heading font-bold text-ink">{problem.heading}</h2>
        <p className="mx-auto mt-4 max-w-[58ch] text-lede text-carbon">{problem.lede}</p>
      </FadeInUp>

      <div className="mt-12 border-t border-silver">
        {problem.items.map((item, i) => (
          <FadeInUp key={item.label} delay={i * 0.06}>
            <div className="grid gap-2 border-b border-silver py-7 md:grid-cols-[180px_1fr] md:gap-10">
              <p className="text-meta text-steel">{item.label}</p>
              <div>
                <h3 className="text-heading-sm font-semibold text-ink">{item.title}</h3>
                <p className="mt-2 max-w-[62ch] text-lede text-carbon">{item.body}</p>
              </div>
            </div>
          </FadeInUp>
        ))}
      </div>
    </Section>
  );
}
