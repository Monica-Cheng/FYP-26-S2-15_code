import Section, { Eyebrow } from "@/components/ui/Section";
import FadeInUp from "@/components/animations/FadeInUp";
import { siteConfig } from "@/content/site-config";

/**
 * Free vs Premium as implemented. Payment collection does not exist yet, and the
 * note under the price says so — the price is what Premium will cost, not
 * something anyone can buy today.
 */
export default function PricingSection() {
  const { pricing } = siteConfig;

  return (
    <Section id="pricing" surface="dark">
      <FadeInUp className="max-w-3xl">
        <Eyebrow tone="dark">{pricing.eyebrow}</Eyebrow>
        <h2 className="mt-3 text-display font-bold text-white">{pricing.heading}</h2>
        <p className="mt-5 max-w-[62ch] text-lede text-silver">{pricing.lede}</p>
      </FadeInUp>

      <FadeInUp delay={0.06}>
        <div className="mt-12 overflow-x-auto">
          <table className="w-full min-w-[640px] border-collapse text-left">
            <thead>
              <tr className="border-b border-white/10">
                <th className="pb-4 pr-6 text-meta font-normal text-fog">What you get</th>
                <th className="w-[200px] pb-4 pr-6 text-meta font-normal text-fog">Free</th>
                <th className="w-[220px] pb-4 align-bottom">
                  <span className="block text-meta font-normal text-fog">Premium</span>
                  <span className="mt-1 block text-heading-sm font-semibold text-white">
                    {pricing.price}
                    <span className="ml-1 text-meta font-normal text-fog">
                      {pricing.priceSuffix}
                    </span>
                  </span>
                </th>
              </tr>
            </thead>
            <tbody>
              {pricing.rows.map((row) => (
                <tr key={row.area} className="border-b border-white/10">
                  <td className="py-4 pr-6 align-top text-lede text-silver">{row.area}</td>
                  <td className="py-4 pr-6 align-top text-lede text-white">{row.free}</td>
                  <td className="py-4 align-top text-lede text-white">{row.premium}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </FadeInUp>

      <FadeInUp delay={0.1}>
        <p className="mt-6 max-w-[62ch] text-meta text-fog">{pricing.priceNote}</p>
      </FadeInUp>
    </Section>
  );
}
