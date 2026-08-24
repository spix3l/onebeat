# Releases, signing and notarization

Pushing a semantic version tag (`vMAJOR.MINOR.PATCH` or `MAJOR.MINOR.PATCH`) runs
`.github/workflows/release.yml`. It builds macOS and Windows x64 archives and
publishes them together in a GitHub release. The tag supplies the application
version; the GitHub run number supplies the monotonically increasing build
number.

The Windows archive is currently unsigned and experimental. Its native WASAPI
backend and Win32 runner compile in CI, but have not been runtime-tested on
Windows hardware by the maintainer. The Windows build also leaves third-party
plug-in hosting disabled until the macOS Mach/POSIX sandbox transport has a
Windows equivalent.

## Opening an unsigned CI build

The archive the release workflow publishes is ad-hoc signed, so it has no team
identifier and no notarization ticket. A download picks up
`com.apple.quarantine`, Gatekeeper finds no ticket, and refuses to launch it
with "Apple could not verify onebeat is free of malware". Confirm what a given
archive actually carries with `codesign -dv --verbose=4 onebeat.app` — an
ad-hoc build reports `Signature=adhoc` and `TeamIdentifier=not set`.

Testers can strip the flag:

```sh
xattr -dr com.apple.quarantine /path/to/onebeat.app
```

or approve it once under System Settings > Privacy & Security > Open Anyway.
Both are per-machine, and neither travels with the archive: everyone who
downloads it hits the same dialog. That is what the Developer ID release below
exists to fix.

## macOS Developer ID release

OneBeat ships outside the Mac
App Store. The App Sandbox is intentionally off
because a DAW must discover plug-ins in system and user Audio/Plug-Ins folders.
Both processes use Hardened Runtime. The main app keeps library validation on;
only `onebeat-plugin-host` receives
`com.apple.security.cs.disable-library-validation`, because it loads arbitrary
third-party CLAP binaries. Neither process receives network, JIT, or unsigned
executable-memory entitlements in Release.

Create a `notarytool` keychain profile once:

```sh
xcrun notarytool store-credentials onebeat-notary \
  --apple-id you@example.com --team-id TEAMID --password APP_PASSWORD
```

To make a signed and notarized package, run locally:

```sh
OB_SIGNING_IDENTITY='Developer ID Application: Name (TEAMID)' \
OB_NOTARY_PROFILE=onebeat-notary tools/release_macos.sh
```

The script builds and tests, signs components inside-out, submits the zip,
staples the app, and runs both `codesign` and Gatekeeper verification. For Gate
G-B, copy the resulting zip to a clean macOS 14+ machine, apply quarantine as a
browser download would, launch it through Finder, and complete the checklist in
`docs/stage-2-closeout.md`. Credentials are never stored in the repository.
