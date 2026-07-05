# YouSound

A personal iOS app: plays the audio track of your own YouTube channel's videos
(and YouTube search results) with CarPlay support. Built in the cloud via
GitHub Actions, installed on iPhone via AltStore.

## What's here
- `Sources/` — the Swift app code
- `project.yml` — project definition (XcodeGen builds the Xcode project from this)
- `.github/workflows/build.yml` — builds an unsigned `YouSound.ipa` on a cloud Mac

## How to get the app
1. Push this repo to GitHub.
2. The Actions workflow runs automatically and produces `YouSound-ipa` as a
   downloadable artifact under the Actions tab.
3. Install that .ipa on your iPhone with AltStore.

Personal use. Extracts audio via YouTubeKit, which is against YouTube's Terms
of Service — use with your own content in mind.
