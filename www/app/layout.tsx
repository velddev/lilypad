import type { ReactNode } from "react";
import "./globals.css";

export const metadata = {
  title: "Lilypad",
  description: "Screenshots and screen recordings for niri.",
  icons: { icon: "/icon.svg" },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
