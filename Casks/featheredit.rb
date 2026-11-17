cask "featheredit" do
  version "1.1.0"
  # Re-generate for every release with scripts/release.sh (it prints the sha256)
  sha256 "9c085e3849d2180b9f2cb6d327e33d8876fda82ce13ef5434d4ecf52c36f5f00"

  url "https://github.com/kdekorte/FeatherEdit/releases/download/v#{version}/FeatherEdit-#{version}.zip"
  name "FeatherEdit"
  desc "Lightweight native macOS text editor"
  homepage "https://github.com/kdekorte/FeatherEdit"

  app "FeatherEdit.app"

  zap trash: [
    "~/Library/Preferences/com.featheredit.app.plist",
  ]
end
