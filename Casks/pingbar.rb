cask "pingbar" do
  version "1.2.0"
  sha256 "cb897e8a6ff9585550ca7196fb3dbee4c20753e7b5d3d02530489c4bacd532d0"

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
