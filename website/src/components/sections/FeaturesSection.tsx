import Section, { Eyebrow } from "@/components/ui/Section";
import FadeInUp from "@/components/animations/FadeInUp";
import PhoneFrame from "@/components/ui/PhoneFrame";
import { siteConfig } from "@/content/site-config";

/**
 * Every row is a real screenshot next to the outcome it produces — headline
 * first, feature name demoted to the eyebrow. The screenshots are the proof
 * that any of this exists.
 */
export default function FeaturesSection() {
  const { features, featuresIntro } = siteConfig;

  return (
    <Section id="features" surface="light">
      <FadeInUp className="mx-auto max-w-3xl text-center">
        <Eyebrow>{featuresIntro.eyebrow}</Eyebrow>
        <h2 className="mt-3 text-heading font-bold text-ink">{featuresIntro.heading}</h2>
      </FadeInUp>

      <div className="mt-16 flex flex-col gap-16 md:gap-24">
        {features.map((feature, i) => (
          <FadeInUp key={feature.eyebrow}>
            <div className="grid items-center gap-10 md:grid-cols-2 md:gap-16">
              <div className={i % 2 === 1 ? "md:order-2" : ""}>
                <Eyebrow>{feature.eyebrow}</Eyebrow>
                <h3 className="mt-3 text-heading-sm font-semibold text-ink">
                  {feature.title}
                </h3>
                <p className="mt-4 text-lede font-medium text-ink">{feature.hook}</p>
                <p className="mt-3 max-w-[56ch] text-lede text-carbon">
                  {feature.explanation}
                </p>
                <p className="mt-5 border-t border-silver pt-4 text-lede font-medium text-ink">
                  {feature.outcome}
                </p>
              </div>

              <div
                className={`flex justify-center ${
                  i % 2 === 1 ? "md:order-1 md:justify-start" : "md:justify-end"
                }`}
              >
                {feature.screens.length === 1 ? (
                  <PhoneFrame
                    src={feature.screens[0].src}
                    alt={feature.screens[0].alt}
                    width={260}
                  />
                ) : (
                  /* Two screens where one screen can't carry the claim — the
                     capture and its result, the chat and the recap. */
                  <div className="flex w-full max-w-[440px] items-start gap-4 sm:gap-6">
                    {feature.screens.map((screen, n) => (
                      <PhoneFrame
                        key={screen.src}
                        src={screen.src}
                        alt={screen.alt}
                        width={205}
                        fluid
                        className={`min-w-0 grow basis-0 ${n === 1 ? "translate-y-8" : ""}`}
                      />
                    ))}
                  </div>
                )}
              </div>
            </div>
          </FadeInUp>
        ))}
      </div>
    </Section>
  );
}
