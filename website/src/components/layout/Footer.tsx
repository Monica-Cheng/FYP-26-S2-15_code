import Image from "next/image";
import Link from "next/link";
import HashLink from "@/components/ui/HashLink";
import { siteConfig } from "@/content/site-config";

export default function Footer() {
  const { academic, footer } = siteConfig;

  return (
    <footer className="bg-midnight px-6 py-16 text-white">
      <div className="mx-auto w-full max-w-[1200px]">
        <div className="grid gap-12 md:grid-cols-[1.4fr_0.8fr_0.8fr]">
          <div className="max-w-sm">
            <Link href="/" className="inline-flex items-center gap-3 rounded-full">
              <Image
                src="/images/logo-mark.png"
                alt=""
                aria-hidden
                width={430}
                height={430}
                className="h-10 w-10 object-contain"
              />
              <span className="text-heading-sm font-semibold text-white">
                {siteConfig.name}
              </span>
            </Link>

            <p className="mt-5 text-meta leading-relaxed text-silver">{footer.blurb}</p>
          </div>

          {footer.groups.map((group) => (
            <div key={group.title}>
              <h2 className="text-meta font-semibold text-white">{group.title}</h2>
              <ul className="mt-4 flex flex-col gap-3">
                {group.links.map((link) => (
                  <li key={link.label}>
                    <HashLink
                      href={link.href}
                      className="rounded-full text-meta text-silver transition-colors hover:text-white"
                    >
                      {link.label}
                    </HashLink>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="mt-14 flex flex-col gap-2 border-t border-white/10 pt-6 md:flex-row md:items-center md:justify-between">
          <p className="text-meta text-silver">
            © 2026 {siteConfig.name}. Pre-launch — no product is on sale.
          </p>
          <p className="text-meta text-fog">
            {academic.group} · {academic.course} · {academic.school} · {academic.year}
          </p>
        </div>
      </div>
    </footer>
  );
}
