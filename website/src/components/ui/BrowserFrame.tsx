import Image from "next/image";

/**
 * Desktop counterpart to PhoneFrame. The administration dashboard is a React web
 * app, not a phone screen, and putting it in a phone would misrepresent it. Plain
 * window chrome, hairline border, no shadow — on the dark surface the border is
 * enough separation.
 */
export default function BrowserFrame({
  src,
  alt,
  width = 1280,
  height = 687,
  className = "",
}: {
  src: string;
  alt: string;
  width?: number;
  height?: number;
  className?: string;
}) {
  return (
    <div
      className={`overflow-hidden rounded-float border border-white/10 bg-midnight ${className}`.trim()}
    >
      <div className="flex items-center gap-2 px-4 py-3">
        <span className="h-2.5 w-2.5 rounded-full bg-white/15" />
        <span className="h-2.5 w-2.5 rounded-full bg-white/15" />
        <span className="h-2.5 w-2.5 rounded-full bg-white/15" />
      </div>
      <Image
        src={src}
        alt={alt}
        width={width}
        height={height}
        sizes="(min-width: 1240px) 1152px, 100vw"
        className="block h-auto w-full"
      />
    </div>
  );
}
