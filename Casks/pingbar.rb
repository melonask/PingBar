cask "pingbar" do
  version "1.3.0"
  sha256 "fe303b5f00dc3e787bfbd63b6f466997e5961d55b2d77ef69dd988f9e1829d4a"

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
      xattr -dr com.apple.quarantine "#{appdir}/PingBar.app"
  EOS
end
