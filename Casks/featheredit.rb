cask "featheredit" do
  version "1.2.1"
  # Re-generate for every release with scripts/release.sh (it prints the sha256)
  sha256 "fdee047a0c3da7c4f673a3f2b87e1131a73bd9e4082a07875784e5674b912c02"

  url "https://github.com/kdekorte/FeatherEdit/releases/download/v#{version}/FeatherEdit-#{version}.zip"
  name "FeatherEdit"
  desc "Lightweight native macOS text editor"
  homepage "https://github.com/kdekorte/FeatherEdit"

  app "FeatherEdit.app"

  zap trash: [
    "~/Library/Preferences/com.featheredit.app.plist",
  ]
end
