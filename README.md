# GDriveBox

Google Drive as a folder in Finder. Files show up instantly and download only when you open them, so they don't fill your Mac.

Website: [gdrivebox.app](https://gdrivebox.app) · Support: [support@gdrivebox.app](mailto:support@gdrivebox.app)

**Status:** early development. Not ready for daily use yet; see [BOARD.md](BOARD.md) for progress.

## Requirements

- Mac with Apple silicon (M1 or later)
- macOS 15 Sequoia or later

## How it works

- A menu-bar app signs you in through Google's own sign-in page (`ASWebAuthenticationSession`), so passkeys and every 2-Step Verification method work.
- A File Provider extension (the same macOS technology iCloud Drive uses) shows your Drive under `~/Library/CloudStorage` and in the Finder sidebar, downloading files on demand.
- Everything runs on your Mac and talks only to Google. There is no GDriveBox server. See the [privacy policy](https://gdrivebox.app/privacy).

## Build from source

Only the Xcode Command Line Tools are needed (Swift 6).

```sh
swift build
swift test          # with Command Line Tools only, re-run once if it fails with "TestingMacros not found"
```

## Layout

| Path | What |
|---|---|
| `Sources/DriveAPI` | Google Drive v3 REST client (token refresh, backoff, paging) |
| `Sources/DriveAuth` | Google sign-in (AppAuth + PKCE), Keychain token storage |
| `docs/` | Website: homepage, privacy policy, terms |
| `BOARD.md` | Kanban board: work in progress and decisions |

## License

[Apache License 2.0](LICENSE)
