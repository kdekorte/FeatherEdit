cask "featheredit" do
  version "1.2.0"
  # Re-generate for every release with scripts/release.sh (it prints the sha256)
  sha256 "3dacc88bdb8a755d2e500223206adf02085ece18836845bb88950a8333f7633c"

  url "https://github.com/kdekorte/FeatherEdit/releases/download/v#{version}/FeatherEdit-#{version}.zip"
  name "FeatherEdit"
  desc "Lightweight native macOS text editor"
  homepage "https://github.com/kdekorte/FeatherEdit"

  app "FeatherEdit.app"

  zap trash: [
    "~/Library/Preferences/com.featheredit.app.plist",
  ]
end
