import Section from "@/components/ui/Section";
import FadeInUp from "@/components/animations/FadeInUp";
import DownloadCta from "@/components/ui/DownloadCta";
import { siteConfig } from "@/content/site-config";

export default function OfferSection() {
  const { offer, ctaNote } = siteConfig;

  return (
    <Section id="join" surface="dark">
      <FadeInUp className="max-w-3xl">
        <h2 className="text-display font-bold text-white">{offer.heading}</h2>
        <p className="mt-5 max-w-[62ch] text-lede text-silver">{offer.lede}</p>
      </FadeInUp>

      <div className="mt-12 grid gap-px overflow-hidden rounded-card border border-white/10 bg-white/10 md:grid-cols-2">
        {offer.items.map((item, i) => (
          <FadeInUp key={item.title} delay={i * 0.05} className="bg-midnight">
            <div className="h-full px-6 py-7">
              <h3 className="text-heading-sm font-semibold text-white">{item.title}</h3>
              <p className="mt-2 text-lede text-silver">{item.body}</p>
            </div>
          </FadeInUp>
        ))}
      </div>

      <FadeInUp delay={0.1}>
        <div className="mt-10 flex flex-col items-start gap-4">
          <DownloadCta />
          <p className="max-w-[62ch] text-meta text-fog">
            {ctaNote} {offer.riskReversal}
          </p>
        </div>
      </FadeInUp>
    </Section>
  );
}
