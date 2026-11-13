cask "featheredit" do
  version "1.0.0"
  # Re-generate for every release with scripts/release.sh (it prints the sha256)
  sha256 "1706d5be170499bd8927e59fd401bf9af193cebe6b249aa6063ca5e6fc1629f6"

  url "https://github.com/kdekorte/FeatherEdit/releases/download/v#{version}/FeatherEdit-#{version}.zip"
  name "FeatherEdit"
  desc "Lightweight native macOS text editor"
  homepage "https://github.com/kdekorte/FeatherEdit"

  app "FeatherEdit.app"

  zap trash: [
    "~/Library/Preferences/com.featheredit.app.plist",
  ]
end
