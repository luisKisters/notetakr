cask "notetakr" do
  version "1.0,85"
  sha256 "dcf9e0665eed3e957174dbff37822d6f20693385468ae105fe6e230bc9416e2a"

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
