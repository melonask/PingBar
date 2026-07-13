# PingBar

A native macOS menu-bar HTTP availability and latency monitor built with SwiftUI. The default endpoint is `https://fast.com`.

| Status | Settings |
| --- | --- |
| ![PingBar status panel](main.png) | ![PingBar settings panel](settings.png) |

## Features

- Configurable HTTP or HTTPS endpoint, interval, and timeout.
- Green, yellow, and red availability states with configurable failure thresholds.
- Current, average, and minimum latency with recent success rate.
- Live chart with green success segments and red failure markers.
- Menu-bar display modes: circle, circle and time, or time.
- Configurable menu-bar text size, circle size, HTTP success range, and chart window.
- Settings stored locally in macOS `UserDefaults`.

## Requirements

- macOS 14 or newer
- Xcode with Swift 6 when building from source

## Build the app

```sh
./scripts/build-app.sh
open PingBar.app
```

This creates an ad-hoc signed `PingBar.app` in the project directory.

## Run

```sh
xcrun swift run PingBar
```

Use **Settings** in the menu to configure monitoring, failure thresholds, chart history, and menu-bar appearance. The indicator is green after a successful request, yellow at the configured warning threshold, and red at the configured failure threshold.

## Test

```sh
xcrun swift test
```

GitHub Actions runs the tests and uploads a packaged `PingBar.app` artifact for every push to `main` and every pull request.
