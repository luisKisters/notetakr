cask "notetakr" do
  version "1.0,76"
  sha256 "fd15c0588b765d79c168e80bb472c7c7627865a438a44cd220d9b8513ebabb1f"

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
