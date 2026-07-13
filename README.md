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

## Download

Download `PingBar.zip` from the latest [GitHub Release](../../releases/latest), unzip it, and open `PingBar.app`. No build tools are required. Because local releases are ad-hoc signed, the first launch may require right-clicking the app and choosing **Open**.

## Build the app

```sh
./scripts/build-app.sh
open PingBar.app
```

This creates an ad-hoc signed `PingBar.app` in the project directory.

The app icon is generated from `logo.svg` and `Resources/AppIcon.svg`. With ImageMagick installed, regenerate it using `./scripts/build-icon.sh`.

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

Pushing a version tag such as `v1.0.0` builds and publishes the ready-to-run `PingBar.zip` on GitHub Releases.
