import type { ReactNode } from "react";

type Surface = "light" | "linen" | "dark" | "darkest";

const surfaces: Record<Surface, string> = {
  light: "bg-canvas text-ink",
  linen: "bg-linen text-ink",
  dark: "bg-deep-indigo text-white",
  darkest: "bg-midnight text-white",
};

/**
 * Every section is a flat colour band. The transition between light and dark
 * is the background-color change and nothing else — no divider, no wave,
 * no diagonal, no gradient fade.
 */
export default function Section({
  id,
  surface = "light",
  className = "",
  containerClassName = "",
  children,
}: {
  id?: string;
  surface?: Surface;
  className?: string;
  containerClassName?: string;
  children: ReactNode;
}) {
  return (
    <section
      id={id}
      className={`${surfaces[surface]} px-6 py-16 md:py-20 ${className}`.trim()}
    >
      <div className={`mx-auto w-full max-w-[1200px] ${containerClassName}`.trim()}>
        {children}
      </div>
    </section>
  );
}

export function Eyebrow({
  children,
  tone = "light",
  className = "",
}: {
  children: ReactNode;
  tone?: "light" | "dark";
  className?: string;
}) {
  return (
    <p
      className={`text-meta ${
        tone === "dark" ? "text-fog" : "text-steel"
      } ${className}`.trim()}
    >
      {children}
    </p>
  );
}
