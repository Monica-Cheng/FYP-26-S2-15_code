"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";

/**
 * next/link treats "/#section" as a navigation to the route you are already on
 * and does nothing with it — the click is swallowed and the page never moves.
 * So an anchor that points at the current page is rendered as a plain <a>, which
 * the browser handles natively: it scrolls, it updates the hash, and it works
 * again on the second click. Off-page anchors keep client-side routing.
 */
export default function HashLink({
  href,
  className = "",
  onClick,
  children,
}: {
  href: string;
  className?: string;
  onClick?: () => void;
  children: ReactNode;
}) {
  const pathname = usePathname();
  const [path, hash] = href.split("#");
  const samePage = Boolean(hash) && (path === "" || path === pathname);

  if (samePage) {
    return (
      <a href={`#${hash}`} className={className} onClick={onClick}>
        {children}
      </a>
    );
  }

  return (
    <Link href={href} className={className} onClick={onClick}>
      {children}
    </Link>
  );
}
