cask "notetakr" do
  version "1.0,72"
  sha256 "d142204083df6070e22014e4c69a756dc6bdbd9d7854657dc56b537eb3ef3567"

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
