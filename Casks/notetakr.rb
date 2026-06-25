cask "notetakr" do
  version "1.0,74"
  sha256 "b7d232492c2390894cdf4dc1877ab4479a98b4d95d6ac3fc23973f4e090c20f0"

  url "https://github.com/luisKisters/notetakr/releases/download/v#{version.csv.first}-#{version.csv.second}/NoteTakr-#{version.csv.first}-#{version.csv.second}.dmg",
      verified: "github.com/luisKisters/notetakr/"
  name "NoteTakr"
  desc "Menu-bar meeting recorder with on-device transcription"
  homepage "https://github.com/luisKisters/notetakr"

  app "NoteTakr.app"

  zap trash: [
    "~/Library/Application Support/NoteTakr",
    "~/Library/Caches/com.notetakr.app",
    "~/Library/HTTPStorages/com.notetakr.app",
    "~/Library/Preferences/com.notetakr.app.plist",
    "~/Library/Saved Application State/com.notetakr.app.savedState",
  ]
end
