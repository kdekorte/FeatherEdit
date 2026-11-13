cask "featheredit" do
  version "1.0.1"
  # Re-generate for every release with scripts/release.sh (it prints the sha256)
  sha256 "d2f7052ce68588dc06bd9a3ffd86c86312ef5dfbce5f29bc2f717cd89fc58e2a"

  url "https://github.com/kdekorte/FeatherEdit/releases/download/v#{version}/FeatherEdit-#{version}.zip"
  name "FeatherEdit"
  desc "Lightweight native macOS text editor"
  homepage "https://github.com/kdekorte/FeatherEdit"

  app "FeatherEdit.app"

  zap trash: [
    "~/Library/Preferences/com.featheredit.app.plist",
  ]
end
