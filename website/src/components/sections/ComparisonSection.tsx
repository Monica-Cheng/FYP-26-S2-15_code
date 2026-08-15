import Section from "@/components/ui/Section";
import FadeInUp from "@/components/animations/FadeInUp";
import { siteConfig } from "@/content/site-config";

/**
 * The page turns dark here. The transition is the background colour and nothing
 * else. Rows concede the competitor's strength first — a page that gives ground
 * is more believable than a column of ticks.
 */
export default function ComparisonSection() {
  const { comparison } = siteConfig;

  return (
    <Section id="comparison" surface="dark">
      <FadeInUp className="max-w-3xl">
        <h2 className="text-display font-bold text-white">{comparison.heading}</h2>
        <p className="mt-5 max-w-[62ch] text-lede text-silver">{comparison.lede}</p>
      </FadeInUp>

      <div className="mt-14">
        <div className="hidden grid-cols-[200px_1fr_1fr] gap-8 border-b border-white/10 pb-3 md:grid">
          <p className="text-meta text-fog">App</p>
          <p className="text-meta text-fog">What it does better than we do</p>
          <p className="text-meta text-fog">What it still leaves you to do</p>
        </div>

        {comparison.rows.map((row, i) => (
          <FadeInUp key={row.name} delay={i * 0.05}>
            <div className="grid gap-3 border-b border-white/10 py-7 md:grid-cols-[200px_1fr_1fr] md:gap-8">
              <h3 className="text-heading-sm font-semibold text-white">{row.name}</h3>
              <p className="text-lede text-silver">{row.credit}</p>
              <p className="text-lede text-white">{row.gap}</p>
            </div>
          </FadeInUp>
        ))}

        <FadeInUp>
          <div className="grid gap-3 py-7 md:grid-cols-[200px_1fr] md:gap-8">
            <h3 className="text-heading-sm font-semibold text-white">
              {siteConfig.name}
            </h3>
            <p className="max-w-[62ch] text-lede text-white">{comparison.close}</p>
          </div>
        </FadeInUp>
      </div>
    </Section>
  );
}
