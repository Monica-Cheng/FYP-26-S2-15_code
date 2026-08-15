export type NotificationAccent = "blue" | "red" | "amber" | "none";

const accents: Record<NotificationAccent, string> = {
  blue: "border-l-[3px] border-signal-blue",
  red: "border-l-[3px] border-alert-red",
  amber: "border-l-[3px] border-amber",
  none: "",
};

/**
 * The signature element. Spent in exactly one place — orbiting the hero phone.
 * Feature rows deliberately do not get one; concentrating it is what makes it
 * read as a signature rather than a motif.
 */
export default function NotificationCard({
  title,
  meta,
  accent = "none",
  className = "",
}: {
  title: string;
  meta: string;
  accent?: NotificationAccent;
  className?: string;
}) {
  return (
    <div
      className={`rounded-[20px] bg-white p-4 shadow-whisper ${accents[accent]} ${className}`.trim()}
    >
      <p className="text-ui font-semibold text-ink">{title}</p>
      <p className="mt-1 text-meta text-steel">{meta}</p>
    </div>
  );
}
