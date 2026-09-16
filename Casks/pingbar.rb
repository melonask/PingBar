cask "pingbar" do
  version "1.4.0"
  sha256 "919c7efa56706293178860f37b10bc01acc68f6bfac78498f451420ac452681f"

  url "https://github.com/melonask/PingBar/releases/download/v#{version}/PingBar.zip"
  name "PingBar"
  desc "Menu-bar monitor for HTTP availability and latency"
  homepage "https://github.com/melonask/PingBar"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "PingBar.app"

  caveats <<~EOS
    PingBar is ad-hoc signed rather than notarized. If macOS blocks the first
    launch, Control-click PingBar.app in Applications and choose Open, or run:
      /usr/bin/xattr -dr com.apple.quarantine "#{appdir}/PingBar.app"
  EOS
end
