cask "pingbar" do
  version "1.5.3"
  sha256 "afb87e4ac2a47e882299b52fdb7d95f823bdab13a764ff968fc21c54a3844b8e"

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
