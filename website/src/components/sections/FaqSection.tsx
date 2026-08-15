import Section from "@/components/ui/Section";
import FadeInUp from "@/components/animations/FadeInUp";
import { siteConfig } from "@/content/site-config";

export default function FaqSection() {
  const { faq } = siteConfig;

  return (
    <Section id="faq" surface="dark">
      <FadeInUp className="max-w-3xl">
        <h2 className="text-display font-bold text-white">{faq.heading}</h2>
      </FadeInUp>

      <div className="mt-12 border-t border-white/10">
        {faq.items.map((item, i) => (
          <FadeInUp key={item.question} delay={i * 0.04}>
            <div className="grid gap-3 border-b border-white/10 py-7 md:grid-cols-[minmax(0,0.9fr)_minmax(0,1.4fr)] md:gap-12">
              <h3 className="text-heading-sm font-semibold text-white">{item.question}</h3>
              <p className="text-lede text-silver">{item.answer}</p>
            </div>
          </FadeInUp>
        ))}
      </div>
    </Section>
  );
}
