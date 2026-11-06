import type { ReactNode } from "react";
import "./globals.css";

const title = "Lilypad: screenshots and screen recordings for niri";
const description =
  "Screenshots and screen recordings for niri on Wayland. Pick a region on a frozen screen by clicking a detected UI element or dragging your own.";
const image = { url: "/og.png", width: 765, height: 408, alt: "The Lilypad toolbar under a selection, with the logo drawn on" };

export const metadata = {
  metadataBase: new URL("https://lilypad.to"),
  title,
  description,
  applicationName: "Lilypad",
  keywords: ["niri", "wayland", "screenshot", "screen recording", "annotation", "linux"],
  alternates: { canonical: "/" },
  icons: { icon: "/icon.svg" },
  openGraph: { type: "website", url: "/", siteName: "Lilypad", title, description, images: [image] },
  twitter: { card: "summary_large_image", title, description, images: [image] },
};

export const viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#eef2ea" },
    { media: "(prefers-color-scheme: dark)", color: "#0e1411" },
  ],
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
