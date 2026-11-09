cask "lampo" do
  version "1.0.0"
  sha256 "2b333aa5e9f9007252027ab5c32528d0e212420d0c8199e82feae422fd84c6b4"

  url "https://github.com/christianmusumeci00/Lampo/releases/download/v#{version}/Lampo-#{version}.zip"
  name "Lampo"
  desc "Apple's on-device model on your selection, screen and clipboard"
  homepage "https://github.com/christianmusumeci00/Lampo"

  livecheck do
    url "https://christianmusumeci00.github.io/Lampo/appcast.xml"
    strategy :sparkle
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :golden_gate

  app "Lampo.app"

  uninstall quit: "app.lampo.Lampo"

  zap trash: [
    "~/Library/Application Support/Lampo",
    "~/Library/Caches/app.lampo.Lampo",
    "~/Library/HTTPStorages/app.lampo.Lampo",
    "~/Library/Preferences/app.lampo.Lampo.plist",
  ]
end
