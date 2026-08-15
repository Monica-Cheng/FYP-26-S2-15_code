import { ButtonLink, type ButtonVariant } from "@/components/ui/Button";
import { siteConfig } from "@/content/site-config";

/**
 * The conversion. One verb, one destination, one place to change either — the
 * build lives on Google Drive rather than a store, so every instance opens in a
 * new tab and carries `siteConfig.ctaNote` nearby.
 */
export default function DownloadCta({
  variant = "amber",
  className = "",
  onClick,
}: {
  variant?: ButtonVariant;
  className?: string;
  onClick?: () => void;
}) {
  return (
    <ButtonLink
      variant={variant}
      href={siteConfig.ctaHref}
      target="_blank"
      rel="noopener noreferrer"
      className={className}
      onClick={onClick}
    >
      {siteConfig.cta}
    </ButtonLink>
  );
}
