import Link from "next/link";
import type { Metadata } from "next";
import { siteConfig } from "@/content/site-config";

export const metadata: Metadata = {
  title: "Admin — WiseWorkout",
};

export default function AdminPage() {
  return (
    <div className="flex min-h-[70vh] flex-col items-center justify-center bg-deep-indigo px-6 py-24 text-center">
      <p className="text-meta text-fog">{siteConfig.academic.group}</p>
      <h1 className="mt-3 text-heading font-bold text-white">Admin</h1>
      <p className="mt-4 max-w-sm text-lede text-silver">
        Posting is handled inside the Updates page. Unlock it there with the admin
        password.
      </p>

      <Link
        href="/updates"
        className="mt-8 inline-flex items-center justify-center rounded-full border border-white/20 px-6 py-3 text-ui font-semibold text-white transition-colors hover:border-white/40 hover:bg-white/[0.06]"
      >
        Go to Updates →
      </Link>
    </div>
  );
}
