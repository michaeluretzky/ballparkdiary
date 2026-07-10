---
name: testflight-auto-push
description: Standing user instruction for the Ballpark Diary iOS app — after ANY code edit to the ios app, automatically push a new build to TestFlight in the same turn. Use this whenever you finish making changes to files under ios/, even if the user's message does not mention TestFlight, publishing, or builds. The user should never have to ask for a TestFlight push again.
---

# Auto-push to TestFlight after every edit

The user has a standing instruction: every time an edit is made to the Ballpark Diary iOS app (any file under `ios/`), push the changes to TestFlight in the same turn — without being asked.

## When this applies

- Any turn where you modify, add, or delete files under `ios/` (app, share extension, tests).
- It does NOT apply to turns that only change `functions/`, docs, screenshots, or answer questions without code changes.
- If the user explicitly says "don't push" or "just preview", skip the push for that turn.

## Steps

1. Finish all code edits for the turn.
2. Run `runChecks({ appPath: "ios" })` and fix any errors until the build passes. Never push a failing build.
3. Follow the app-store-publish skill (`.rork/skills/app-store-publish/SKILL.md`) TestFlight flow. In practice for this project that is:
   - `setupAsc` (if the Apple session is expired, re-authenticate with `connectAppleDeveloper`, then `setupAsc` again)
   - `ensureCertificate`, `ensureApp`, `syncCapabilities`
   - Read the marketing version from `ios/BallparkDiary.xcodeproj/project.pbxproj` (MARKETING_VERSION)
   - `submitBuild`
4. In the final message, mention the build number that was submitted along with the summary of changes.

## Notes

- The TestFlight invite/distribution is handled automatically after upload; no extra steps needed.
- If the upload fails for an unrecoverable reason, tell the user clearly that the code changes are done but the TestFlight push failed, and why.
