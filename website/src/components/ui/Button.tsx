import Link from "next/link";
import type { ComponentProps, ReactNode } from "react";

/**
 * Four variants, three of which are role-locked:
 *   amber  — the single conversion action (siteConfig.cta). Nowhere else.
 *   blue   — at most one filled #007bff button per surface (modal + admin form).
 *   ghost  — secondary action on light. Black outline, never blue.
 *   ghostDark — secondary action on dark.
 * No hover scale, no gradient, no coloured shadow. Colour shift only.
 */
export type ButtonVariant = "amber" | "blue" | "ghost" | "ghostDark";

const base =
  "inline-flex items-center justify-center gap-2 rounded-full px-6 py-3 text-ui font-semibold transition-colors duration-200 disabled:cursor-not-allowed disabled:opacity-60";

const variants: Record<ButtonVariant, string> = {
  amber: "bg-amber text-ink hover:bg-[#e0ac00]",
  blue: "bg-signal-blue text-white hover:bg-[#0069d9]",
  ghost:
    "border border-ink/50 bg-transparent text-ink hover:border-ink hover:bg-ink/[0.04]",
  ghostDark:
    "border border-white/20 bg-transparent text-white hover:border-white/40 hover:bg-white/[0.06]",
};

export function buttonClass(variant: ButtonVariant, className = "") {
  return `${base} ${variants[variant]} ${className}`.trim();
}

export function Button({
  variant = "amber",
  className,
  children,
  ...props
}: { variant?: ButtonVariant; children: ReactNode } & ComponentProps<"button">) {
  return (
    <button className={buttonClass(variant, className)} {...props}>
      {children}
    </button>
  );
}

export function ButtonLink({
  variant = "ghost",
  className,
  href,
  children,
  ...props
}: {
  variant?: ButtonVariant;
  href: string;
  className?: string;
  children: ReactNode;
} & Omit<ComponentProps<typeof Link>, "href" | "className">) {
  return (
    <Link href={href} className={buttonClass(variant, className)} {...props}>
      {children}
    </Link>
  );
}
