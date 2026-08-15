import Section from "@/components/ui/Section";
import FadeInUp from "@/components/animations/FadeInUp";
import { siteConfig } from "@/content/site-config";

/**
 * One hairline-divided slab, not four floating stat cards — that is what makes
 * it read as an instrument panel. The lede states outright that these are one
 * test account's numbers, because unlabelled figures on a dark slab read as
 * aggregate user traction, and there is no traction to report.
 */
export default function StatsSection() {
  const { stats } = siteConfig;

  return (
    <Section surface="dark">
      <FadeInUp className="max-w-3xl">
        <h2 className="text-display font-bold text-white">{stats.heading}</h2>
        <p className="mt-5 max-w-[62ch] text-lede text-silver">{stats.lede}</p>
      </FadeInUp>

      <FadeInUp delay={0.08}>
        {/* gap-px over a light background paints the hairline grid at every
            breakpoint without per-cell border bookkeeping */}
        <div className="mt-12 grid gap-px overflow-hidden rounded-card border border-white/10 bg-white/10 sm:grid-cols-2 lg:grid-cols-4">
          {stats.items.map((item) => (
            <div key={item.label} className="bg-midnight px-6 py-8">
              <p className="text-display font-bold text-white">{item.value}</p>
              <p className="mt-3 text-meta text-fog">{item.label}</p>
            </div>
          ))}
        </div>
      </FadeInUp>
    </Section>
  );
}
