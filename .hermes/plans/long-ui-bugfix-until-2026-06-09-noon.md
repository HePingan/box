# Long UI + Bugfix Work Plan (2026-06-08 → 2026-06-09 12:00)

> **For Hermes:** Continue autonomously in verified batches. Prioritize existing bugs and visible Flutter UI defects. Default to Web-only verification; do not build APK unless the user explicitly asks later.

**Goal:** Work until around 2026-06-09 12:00 local time, continuously improving the Flutter app while preserving progress against network/API interruptions.

**Architecture:** Use short, restartable batches. Each batch discovers concrete bugs via analyzer/tests/static scans/UI inspection, fixes root causes, verifies with `dart format`, `flutter analyze`, relevant tests when available, and Web preview HTTP 200. Save progress after each verified batch with a local progress log and git commit when changes are coherent.

**Tech Stack:** Flutter/Dart project at `/c/Users/Admin/box-inspect`, Windows host via Git Bash, China Flutter/Pub mirrors.

---

## Operating Rules

1. **Primary objective:** fix existing bugs first, then continue UI polish where it reduces visible defects.
2. **Default verification:** Web only. Restart/verify `flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080`; confirm `GET /` returns HTTP 200.
3. **No APK builds** unless explicitly requested later.
4. **Progress safety:** after every verified coherent batch:
   - append `.hermes/progress/long-ui-bugfix-log.md`;
   - run `git status --short`;
   - commit the coherent batch with a descriptive message.
5. **If network/API/tool errors happen:** preserve current findings and partial work in `.hermes/progress/long-ui-bugfix-log.md`; do not discard useful partial edits. On next run, inspect `git diff` and continue.
6. **Do not recursively schedule cron jobs.**

## Environment

Use this before Flutter commands:

```bash
export JAVA_HOME=/c/tools/jdk17/jdk-17.0.19+10
export ANDROID_SDK_ROOT=/c/Android/Sdk
export ANDROID_HOME=/c/Android/Sdk
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export PATH="/c/tools/flutter-sdk/flutter/bin:$JAVA_HOME/bin:/c/Android/Sdk/cmdline-tools/latest/bin:/c/Android/Sdk/platform-tools:$PATH"
```

## Batch Backlog

### Batch 0: Checkpoint current B3 UI compression
- Verify current modifications.
- Run `dart format` and `flutter analyze`.
- Restart/verify Web preview HTTP 200.
- Commit current coherent UI compression if not already committed.

### Batch 1: Static bug scan
- Run `flutter test` if tests are present.
- Search for risky patterns: async context use, `TODO`, `FIXME`, `print(`, broad `catch (_)`, empty error states, missing mounted checks.
- Pick the highest-risk reproducible issue and fix root cause.

### Batch 2: Navigation/bottom-overlap bugs
- Inspect all bottom-tab pages for insufficient bottom padding.
- Fix last-card/nav overlap and scroll clipping.
- Verify on Web.

### Batch 3: Text overflow and card density bugs
- Search/inspect pages for long Chinese/English labels in cards/buttons.
- Add `maxLines`, ellipsis, shorter copy, or adjusted aspect ratios.
- Verify analyzer and Web.

### Batch 4: Content and plugin state bugs
- Inspect content/warehouse and plugin import/export flows.
- Fix obvious error-state, empty-state, mounted-context, and dialog layout issues.

### Batch 5+: Self-generate next plan
After the above, create the next short plan based on:
- current `flutter analyze`/test output;
- `git diff`/status;
- largest files and risky patterns;
- visible mobile defects in primary routes.

Continue until around 2026-06-09 12:00 local time, then produce a final summary in chat with commits, verification status, and remaining risks.
