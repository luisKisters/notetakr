cask "notetakr" do
  version "1.0,83"
  sha256 "1f8a557efe60d118ee3e135fbba4b20470411a9ea94c18952b11a993c0968745"

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
