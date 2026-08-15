"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { useScroll, useMotionValueEvent } from "framer-motion";
import { Menu, X } from "lucide-react";
import { siteConfig } from "@/content/site-config";
import DownloadCta from "@/components/ui/DownloadCta";
import HashLink from "@/components/ui/HashLink";

export default function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const { scrollY } = useScroll();
  const pathname = usePathname();

  useMotionValueEvent(scrollY, "change", (y) => setScrolled(y > 16));

  useEffect(() => {
    document.body.style.overflow = mobileOpen ? "hidden" : "";
    return () => {
      document.body.style.overflow = "";
    };
  }, [mobileOpen]);

  return (
    <>
      <div className="fixed inset-x-0 top-0 z-50">
        {/* Announcement bar — build status, sets the control-room tone */}
        <div className="bg-deep-indigo px-4 py-2 text-center">
          <p className="text-meta font-medium text-white">
            {siteConfig.announcement.text}
            <span aria-hidden className="mx-2 text-white/30">
              ·
            </span>
            <a
              href={siteConfig.ctaHref}
              target="_blank"
              rel="noopener noreferrer"
              className="underline decoration-white/30 underline-offset-4 transition-colors hover:decoration-white"
            >
              {siteConfig.announcement.linkLabel} →
            </a>
          </p>
        </div>

        {/* Floating pill — sits on the page like a device, not a structural bar */}
        <div className="px-4 pt-3">
          <nav
            className={`mx-auto flex max-w-[1200px] items-center justify-between gap-4 rounded-full border border-silver bg-white px-3 py-2 transition-shadow duration-300 md:px-4 ${
              scrolled ? "shadow-nav" : ""
            }`}
          >
            {/* Mark + live wordmark. The mark asset has no lettering of its own,
                and system-ui type stays crisp at every density. */}
            <Link
              href="/"
              className="flex shrink-0 items-center gap-2 rounded-full pl-1"
            >
              <Image
                src="/images/logo-mark.png"
                alt=""
                aria-hidden
                width={430}
                height={430}
                priority
                className="h-7 w-7 object-contain md:h-8 md:w-8"
              />
              <span className="text-ui font-semibold tracking-[-0.02em] text-ink">
                {siteConfig.name}
              </span>
            </Link>

            <ul className="hidden items-center gap-6 md:flex">
              {siteConfig.navLinks.map((link) => {
                const active = pathname === link.href;
                return (
                  <li key={link.href}>
                    <HashLink
                      href={link.href}
                      className={`rounded-full text-ui font-medium transition-colors ${
                        active ? "text-signal-blue" : "text-ink hover:text-steel"
                      }`}
                    >
                      {link.label}
                    </HashLink>
                  </li>
                );
              })}
            </ul>

            {/* wrapper carries the breakpoint: `hidden` on the button itself
                would fight the `inline-flex` in buttonClass's base */}
            <div className="hidden shrink-0 md:block">
              <DownloadCta variant="ghost" className="px-4 py-2" />
            </div>

            <button
              type="button"
              onClick={() => setMobileOpen((v) => !v)}
              aria-label={mobileOpen ? "Close menu" : "Open menu"}
              aria-expanded={mobileOpen}
              className="inline-flex h-9 w-9 items-center justify-center rounded-full border border-ink/50 text-ink md:hidden"
            >
              {mobileOpen ? <X className="h-4 w-4" /> : <Menu className="h-4 w-4" />}
            </button>
          </nav>
        </div>
      </div>

      {/* Spacer: announcement bar + pill gutter + pill */}
      <div aria-hidden className="h-[96px] md:h-[100px]" />

      {/* Mobile sheet */}
      {mobileOpen ? (
        <div className="fixed inset-0 z-40 flex flex-col bg-white px-6 pb-8 pt-[112px] md:hidden">
          <ul className="flex flex-col gap-1">
            {siteConfig.navLinks.map((link) => (
              <li key={link.href}>
                <HashLink
                  href={link.href}
                  onClick={() => setMobileOpen(false)}
                  className="block rounded-lg py-3 text-heading-sm font-semibold text-ink"
                >
                  {link.label}
                </HashLink>
              </li>
            ))}
          </ul>
          <div className="mt-6">
            <DownloadCta className="w-full" onClick={() => setMobileOpen(false)} />
            <p className="mt-3 text-meta text-steel">{siteConfig.ctaNote}</p>
          </div>
        </div>
      ) : null}
    </>
  );
}
