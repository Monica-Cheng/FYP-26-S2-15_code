import HeroSection from "@/components/sections/HeroSection";
import ProblemSection from "@/components/sections/ProblemSection";
import MechanismSection from "@/components/sections/MechanismSection";
import AdaptiveSection from "@/components/sections/AdaptiveSection";
import FeaturesSection from "@/components/sections/FeaturesSection";
import PersonasSection from "@/components/sections/PersonasSection";
import CoachesSection from "@/components/sections/CoachesSection";
import ComparisonSection from "@/components/sections/ComparisonSection";
import PricingSection from "@/components/sections/PricingSection";
import OfferSection from "@/components/sections/OfferSection";
import BuiltInPublicSection from "@/components/sections/BuiltInPublicSection";
import FaqSection from "@/components/sections/FaqSection";
import FinalCtaSection from "@/components/sections/FinalCtaSection";

export default function HomePage() {
  return (
    <>
      {/* White surface: what it is, how you start, what it does, who it's for */}
      <HeroSection />
      <ProblemSection />
      <MechanismSection />
      <AdaptiveSection />
      <FeaturesSection />
      <PersonasSection />
      <CoachesSection />

      {/* Drops to the dark control room and stays there through the footer */}
      <ComparisonSection />
      <PricingSection />
      <OfferSection />
      <BuiltInPublicSection />
      <FaqSection />
      <FinalCtaSection />
    </>
  );
}
