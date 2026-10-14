cask "pingbar" do
  version "1.5.2"
  sha256 "7caeb775458b6ba1c9f0dcef2bb633f6c8b7e5700a36d3d882084a4f84d38e54"

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
