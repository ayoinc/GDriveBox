# GDriveBox Kanban Board

Source of truth for work on GDriveBox. Walk it right-to-left (Done → Blocked) at the start of every session.

## Policies

| Policy | Rule |
|---|---|
| WIP: In Progress | **2** — set by the team 2026-10-10. Hypothesis: re-measure after two weeks. |
| WIP: Verify | **2** — matches In Progress (Jev abstained 2 vs 1 at 0.64; revisit with data). |
| WIP: Expedite | **1**, bypasses other limits. |
| Blocked lane | Cards waiting on an external action. Excluded from WIP. Each names its owner and unblock condition. |
| Classes of service | **Expedite**: crisis only (data loss, token leak, broken sync for users). **Standard**: default, FIFO. **Intangible**: CI, tooling, docs; pulled only when no Standard card is Ready. |
| Pull order | Expedite → Standard (FIFO) → Intangible. |
| Definition of Ready | Acceptance criteria written; no unresolved external dependency. |
| Definition of Done | `swift build` and `swift test` pass; the changed behavior was exercised by a smoke run (or the card states which part is blocked and why); board updated; Jev acceptance check returns act/review. |
| Decisions | Ask Jev first at every decision point. Abstains go to the human. |

Cycle time = Done date − Started date (calendar days). Track it per class.

## Open decisions (Jev abstained → human)

| Decision | Jev lean | Where it lands |
|---|---|---|
| Verify WIP limit 2 vs 1 | 2 (0.64) | Policy above; revisit with two weeks of data. |
| Sign-in reuses the Safari Google session vs. a private (ephemeral) session | reuse (0.64) | Resolved 2026-10-10: reuse (user asked to plow through decisions; Jev's lean taken). |
| Commit each card to git when it reaches Done | no lean (0.48) | Resolved 2026-10-10: commit per card, Conventional Commits, pushed to public `ayoinc/GDriveBox` (user chose a public repo). |
| Create the File Provider extension's provisioning profile now | no (0.27) | Resolved 2026-10-10 in S-07: created "GDriveBox FileProvider macOS Development". |
| File Provider domain identifier: fixed `google` vs the account email | email (0.59, abstain) | Resolved 2026-10-10: fixed `google`, display name "GDriveBox" (card spec; one account at a time). Folder: `~/Library/CloudStorage/GDriveBox-GDriveBox`. |

## Accounts and identifiers

| Thing | Value |
|---|---|
| Apple team | Ayodele Ajayi (Individual), Team ID `T8242XY72S` (user excluded the Kharis Ministries team) |
| App IDs | `io.github.ayoinc.GDriveBox`, `io.github.ayoinc.GDriveBox.FileProvider` (App Groups enabled) |
| App group / keychain access group | `group.io.github.ayoinc.GDriveBox` |
| App Store Connect | GDriveBox, macOS, Apple ID `6821382130`, SKU `gdrivebox-macos`, English (U.K.) |
| Dev signing | `Apple Development: Ayodele Ajayi (747Y7L4FPC)` (key only in login keychain); this Mac registered (device "MacBook Pro M5 Pro GDriveBox dev"); profiles "GDriveBox macOS Development" (app, `98073db9-…`) and "GDriveBox FileProvider macOS Development" (extension, `b31757c0-a86c-4de6-b7ac-7f4362c96f04`, portal ID `VW62R42V53`, expires 2027-10-10) |
| Google Cloud | project `gdrivebox-ayoinc`; Drive API enabled; OAuth app **In production**, unverified (100-user lifetime cap, "unverified app" screen) |
| Google OAuth client (iOS type, public) | `473211601147-pdhd9n52ki3832vaddcsaceo8bktgk4p.apps.googleusercontent.com` |
| Website | https://gdrivebox.app/ (also www): Cloudflare Worker `gdrivebox-site` serving `docs/` as static assets (`site/wrangler.jsonc`, deploy: `cd site && npx wrangler deploy`); binding `EMAIL` (Send Email) reserved, unused. The old GitHub Pages URLs redirect to gdrivebox.app. |
| Email | `support@gdrivebox.app` is the only public contact; Cloudflare Email Routing catch-all forwards all `@gdrivebox.app` mail to the owner's inbox. |

## Done

| Card | Class | Started | Done |
|---|---|---|---|
| S-01 Repo bootstrap | Standard | 2026-10-10 | 2026-10-10 |
| S-02 DriveAPI client — 10 Swift Testing tests (incl. 11-case retry classification); live smoke vs `www.googleapis.com` (real 401 parsed, single forced refresh). Authenticated listing exercised in S-06 (needs B-03). | Standard | 2026-10-10 | 2026-10-10 |
| S-03 DriveAuth — 8 Swift Testing tests (stubbed token endpoint through AppAuth's HTTP stack); smoke: login-keychain round trip, unsigned data-protection keychain → `-34018`, refresh against real `oauth2.googleapis.com` surfaces `invalid_client`. Interactive passkey/MFA sign-in and a successful real refresh exercised in S-06. | Standard | 2026-10-10 | 2026-10-10 |
| A-01 Apple setup — identifiers, app group, App Store Connect record, dev certificate, device, dev profile (all verified in the portal / decoded profile) | Standard | 2026-10-10 | 2026-10-10 |
| G-01 Google OAuth — project, Drive API, branding, scopes, iOS client, published to production (Audience page shows "In production"); branding now on gdrivebox.app (home, `/privacy`, `/terms`, authorised domain `gdrivebox.app`, developer contact `support@gdrivebox.app`) | Standard | 2026-10-10 | 2026-10-10 |
| P-01 Public repo + website — `ayoinc/GDriveBox` public; homepage, privacy policy (Limited Use statement), terms | Standard | 2026-10-10 | 2026-10-10 |
| W-01 gdrivebox.app — Worker `gdrivebox-site` on apex + www (all URLs 200), contact `support@gdrivebox.app`, old GitHub Pages URLs redirect | Standard | 2026-10-10 | 2026-10-10 |
| S-05′ App bundle without Xcode — `Scripts/build-app.sh` (shellcheck clean) builds arm64 `GDriveBox.app`; ad-hoc and profile-signed builds verify and launch; signed build restores from the app-group keychain without `-34018` | Standard | 2026-10-10 | 2026-10-10 |

## Verify

- **S-06 Menu-bar sign-in + debug listing** · Standard · started 2026-10-10 · waiting on the human
  - Built and running signed (`build/GDriveBox.app`). Remaining AC: the user signs in once with a passkey and once with another MFA method; the window lists the My Drive root and storage usage.
- **S-07/S-08 Finder folder: domain, enumeration, on-demand download** · Standard · started 2026-10-10 · waiting on the human
  - Done: `GDriveBoxFileProvider.appex` (`NSFileProviderReplicatedExtension`, SwiftPM executable entering `NSExtensionMain`) embedded and signed with its own profile; `pluginkit` lists it; app registers domain `google` ("GDriveBox") on sign-in/launch/Refresh → `~/Library/CloudStorage/GDriveBox-GDriveBox` exists. `item(for:)` = `files.get`, folder enumerator pages `files.list` via `NSFileProviderPage`, `fetchContents` = `files.get?alt=media` streamed to a temp file; Google-native docs served as generated `.webloc` links (Jev act 0.98); read-only (capabilities read/enumerate only; create/modify → `NSFeatureUnsupportedError`, delete → `deletionRejected`). Extension reads tokens from the app-group keychain item. 15 DriveAPI + 10 extension tests.
  - Remaining AC: macOS lists the domain as "user-disabled" until the user turns GDriveBox on (System Settings › General › Login Items & Extensions › File Providers; the window shows a banner + button). Then: `ls ~/Library/CloudStorage/GDriveBox-GDriveBox` lists My Drive root dataless; opening a file downloads it.
  - Not yet: remote changes (fixed sync anchor until S-10), writes (S-09).
- **S-12a Sign out** · Standard · started 2026-10-10 · waiting on the human
  - Done: "Sign Out" in the menu and the window header → revoke at `oauth2.googleapis.com/revoke` (400 `invalid_token` = already revoked; offline → local sign-out continues with a notice, Jev act 0.98), delete the keychain item, `NSFileProviderManager.remove(…, mode: .removeAll)`, reset UI. 4 revocation tests.
  - Remaining AC: exercise it on the user's real session (signs them out, so left to the user): domain and folder gone, app shows "Not signed in".
  - Verify holds 3 cards (limit 2): all three wait on the same human session.

## In Progress (WIP 2)

_(empty)_

## Ready

- **S-04 MetadataStore** · Standard — GRDB SQLite (WAL) in the App Group: items, sync_state (changes pageToken), uploads.

## Backlog

### Milestone 2+
- **S-09 Uploads + create/modify/delete** · Standard — multipart ≤ 5 MB, resumable above; delete → Drive Trash.
- **S-10 Remote change polling** · Standard — 60 s + wake/network/activation; extension alone advances the pageToken.
- **S-11 Conflicts: keep both** · Standard
- **S-12 Onboarding, status** · Standard — sign-out split out as S-12a.
- **S-13 Release pipeline** · Standard — Developer ID, notarization, Sparkle, Homebrew cask (arm64, macOS ≥ 15).
- **I-01 CI** · Intangible — GitHub Actions `swift build` + `swift test` on an Apple-silicon runner.
- **I-02 CONTRIBUTING** · Intangible (README shipped with P-01)
- **I-03 swift-format config** · Intangible
- **I-04 Test-build flake** · Intangible — with Command Line Tools only, `swift test` (default `swiftbuild` backend) alternates: one run fails with "plugin for module 'TestingMacros' not found", the next passes. `--build-system native` cannot find `Testing` at all. Workaround: re-run.
- **I-05 SwiftUI macros without Xcode** · Intangible — the macOS 27 SDK makes `@State` (and `@Entry`, `#Preview`) macros whose plugin ships only with Xcode; the app uses `State(initialValue:)` directly. Revisit if Command Line Tools start shipping SwiftUIMacros.

## Blocked

- **B-04 Google restricted-scope verification** (owner: human, then agent) — needs: Search Console ownership of `gdrivebox.app` (automated clicks are ignored by Search Console inside the cmux browser, so the human adds a Domain property and approves Cloudflare's DNS verification), a demo video of the working app showing the consent flow and Drive use (needs S-06/S-08), and the "Backup and sync" scope justification. Until verified: "unverified app" screen and a 100-user lifetime cap.
- **B-06 Google "User support email" on @gdrivebox.app** (owner: human) — the field only accepts the signed-in Google account or a Google Group it manages (today: the owner's Gmail). Option: create a Google account for `support@gdrivebox.app` (mail already forwards), add it as project Owner, then select it.
- **B-05 Developer ID Application certificate** (owner: agent, in S-13) — needed to sign builds for other people's Macs; Account Holder role confirmed.

## Dropped

- B-01 Install Xcode — user chose the no-Xcode build (2026-10-10).
- S-05 XcodeGen project — replaced by S-05′.
