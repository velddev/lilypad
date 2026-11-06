import Picker from "./Picker";

const app = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "Lilypad",
  url: "https://lilypad.to",
  image: "https://lilypad.to/og.png",
  description: "Screenshots and screen recordings for niri on Wayland.",
  applicationCategory: "MultimediaApplication",
  operatingSystem: "Linux",
};

export default function Page() {
  return (
    <>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(app) }} />
      <Picker />
    </>
  );
}
