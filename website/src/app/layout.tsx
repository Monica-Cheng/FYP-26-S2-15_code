import type { Metadata } from "next";
import "./globals.css";
import Navbar from "@/components/layout/Navbar";
import Footer from "@/components/layout/Footer";
import WaitlistModalProvider from "@/components/waitlist/WaitlistModalProvider";
import { siteConfig } from "@/content/site-config";

export const metadata: Metadata = {
  title: `${siteConfig.name} — ${siteConfig.tagline}`,
  description: siteConfig.description,
  icons: {
    icon: "/images/logo-mark.png",
    shortcut: "/images/logo-mark.png",
    apple: "/images/logo-mark.png",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="flex min-h-full flex-col bg-canvas text-ink">
        <WaitlistModalProvider>
          <Navbar />
          <main className="flex-1">{children}</main>
          <Footer />
        </WaitlistModalProvider>
      </body>
    </html>
  );
}
