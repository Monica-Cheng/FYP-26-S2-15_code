"use client";

import Section from "@/components/ui/Section";
import FadeInUp from "@/components/animations/FadeInUp";
import DownloadCta from "@/components/ui/DownloadCta";
import { useWaitlistModal } from "@/components/waitlist/WaitlistModalProvider";
import { siteConfig } from "@/content/site-config";

export default function FinalCtaSection() {
  const { openModal } = useWaitlistModal();
  const { finalCta, ctaNote } = siteConfig;

  return (
    <Section surface="dark" className="py-24 md:py-32">
      <FadeInUp className="mx-auto max-w-2xl text-center">
        <h2 className="text-display font-bold text-white">{finalCta.heading}</h2>
        <p className="mx-auto mt-5 max-w-[52ch] text-lede text-silver">{finalCta.lede}</p>

        <div className="mt-8 flex justify-center">
          <DownloadCta />
        </div>

        <p className="mt-4 text-meta text-fog">
          {ctaNote} {finalCta.riskReversal}
        </p>

        {/* The only remaining way into the mailing list. Text link, not a second
            button — the download is the action on this surface. */}
        <p className="mt-8 text-meta text-fog">
          {finalCta.waitlistPrompt}{" "}
          <button
            type="button"
            onClick={openModal}
            className="rounded-full text-white underline decoration-white/30 underline-offset-4 transition-colors hover:decoration-white"
          >
            {finalCta.waitlistLink}
          </button>
        </p>
      </FadeInUp>
    </Section>
  );
}
