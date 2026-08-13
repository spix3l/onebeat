# macOS release and notarization

OneBeat is not being published yet. This document and the local script are kept
only to validate the architecture when release work resumes; there is no CI
release job and no command here uploads a public release.

When distribution work resumes, OneBeat is expected to ship outside the Mac
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

When Gate G-B is explicitly scheduled, run locally:

```sh
OB_SIGNING_IDENTITY='Developer ID Application: Name (TEAMID)' \
OB_NOTARY_PROFILE=onebeat-notary tools/release_macos.sh
```

The script builds and tests, signs components inside-out, submits the zip,
staples the app, and runs both `codesign` and Gatekeeper verification. For Gate
G-B, copy the resulting zip to a clean macOS 14+ machine, apply quarantine as a
browser download would, launch it through Finder, and complete the checklist in
`docs/stage-2-closeout.md`. Credentials are never stored in the repository.
