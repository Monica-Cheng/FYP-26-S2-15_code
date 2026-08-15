import Link from "next/link";
import Section from "@/components/ui/Section";
import FadeInUp from "@/components/animations/FadeInUp";
import { siteConfig } from "@/content/site-config";

/**
 * The honest proof section. It replaces the press grid and award badges from the
 * reference, which have no truthful equivalent for a pre-launch student project.
 */
export default function BuiltInPublicSection() {
  const { builtInPublic } = siteConfig;

  return (
    <Section surface="dark">
      <FadeInUp className="max-w-3xl">
        <h2 className="text-display font-bold text-white">{builtInPublic.heading}</h2>
        <p className="mt-5 max-w-[62ch] text-lede text-silver">{builtInPublic.lede}</p>
      </FadeInUp>

      <div className="mt-12 grid gap-px overflow-hidden rounded-card border border-white/10 bg-white/10 md:grid-cols-3">
        {builtInPublic.items.map((item, i) => (
          <FadeInUp key={item.title} delay={i * 0.05} className="bg-midnight">
            <div className="flex h-full flex-col px-6 py-7">
              <h3 className="text-heading-sm font-semibold text-white">{item.title}</h3>
              <p className="mt-2 flex-1 text-lede text-silver">{item.body}</p>
              <Link
                href={item.href}
                className="mt-5 inline-flex w-fit rounded-full text-ui font-medium text-white underline decoration-white/30 underline-offset-4 transition-colors hover:decoration-white"
              >
                {item.linkLabel} →
              </Link>
            </div>
          </FadeInUp>
        ))}
      </div>
    </Section>
  );
}
