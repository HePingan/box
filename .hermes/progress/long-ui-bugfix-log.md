# Long UI + Bugfix Progress Log

## 2026-06-08 21:29 local
- User requested autonomous long-running work until around 2026-06-09 12:00.
- Primary focus: fix existing bugs; continue UI optimization after each plan; save progress against network/API errors.
- Created plan: `.hermes/plans/long-ui-bugfix-until-2026-06-09-noon.md`.
- Starting state: modified `lib/home_page.dart`, `lib/main.dart`, `lib/plugin_tab.dart`, `lib/tool_page.dart`, `lib/warehouse_tab.dart` from B3 UI compression; branch `master`.

## 2026-06-08 21:34 local - Batch 0 checkpoint
- Files touched: `lib/home_page.dart`, `lib/main.dart`, `lib/plugin_tab.dart`, `lib/tool_page.dart`, `lib/warehouse_tab.dart`.
- Bug/root cause: prior B3 UI compression addressed visible mobile defects: oversized hero sections, long product labels, bottom-nav occupying too much height, and shortcut cards prone to truncation/overlap.
- Fix: compressed first-screen hero/card/nav density, shortened labels, increased bottom spacer behind floating nav.
- Verification: `dart format` reported 0 changed; `flutter analyze` returned `No issues found!`; Web preview `GET /` returned `code=200 size=1494`.
- Notes: first web-server restart attempt hit port 8080 already bound by this project's Flutter web-server; verified the existing project server is healthy instead of killing unrelated cpolar tunnel.
- Remaining risks: next batch should run tests/static bug scan and fix concrete non-cosmetic issues.

## 2026-06-08 21:37 local — Batch 0 checkpoint
- Files touched: `lib/home_page.dart`, `lib/main.dart`, `lib/plugin_tab.dart`, `lib/tool_page.dart`, `lib/warehouse_tab.dart`, `.hermes/progress/long-ui-bugfix-log.md`.
- Bug/root cause: B3 UI compression work was present in the working tree but not yet checkpointed; risk was losing verified layout changes during later bugfix batches.
- Fix: formatted the touched Dart files and restarted the Flutter Web preview after stopping only the existing project web-server processes on port 8080. Left unrelated tunnel/static preview tools (for example cpolar and Python servers) untouched.
- Verification output:
  - `dart format lib/home_page.dart lib/main.dart lib/plugin_tab.dart lib/tool_page.dart lib/warehouse_tab.dart` → `Formatted 5 files (0 changed)`.
  - `flutter analyze` → `No issues found! (ran in 8.2s)`.
  - `curl -sS -o /tmp/flutter_preview.html -w 'code=%{http_code} size=%{size_download}\n' http://127.0.0.1:8080/` → `code=200 size=1494`.
- Remaining risks: no targeted tests were run in this checkpoint because the batch only verified existing UI compression changes; next batch should start the static/test bug scan from Batch 1.

## 2026-06-08 21:45 local — Batch 1 static/test scan
- Files touched: `.hermes/progress/long-ui-bugfix-log.md` only.
- Bug/root cause: continued systematic investigation after checkpointing B3. Full regression tests and analyzer are currently green; no reproducible code bug was isolated in this scan, so no speculative source fix was made.
- Evidence gathered:
  - `flutter test` → `00:08 +40: All tests passed!`.
  - `flutter analyze` from Batch 0 → `No issues found!`.
  - Active route scan found existing guarded bottom spacers on the four shell pages: `home_page.dart`, `tool_page.dart`, `warehouse_tab.dart`, `plugin_tab.dart`; `AppTokens.pageBottomPadding` is 112.
  - Risk scan found broad/silent catches mostly in cache/fallback paths under novel repositories; these need targeted reproduction before editing.
- Fix: none; deliberately avoided changing source without a root cause.
- Verification output: Web preview remains healthy from Batch 0 with `GET /` returning `code=200 size=1494`; no code edits requiring another restart.
- Remaining risks / next recovery step: Batch 2 should inspect concrete navigation/dialog layout behavior (especially bootstrap book-source dialog and long text on small widths) and create a targeted fix only if a reproducible layout or async-context issue is confirmed.

## 2026-06-08 21:55 local — Batch 2 bottom-overlap fix
- Files touched: `lib/novel/pages/novel_list_page.dart`, `lib/plugin_tab.dart`, `lib/video-Pro/pages/video_sliver_home.dart`, `.hermes/progress/long-ui-bugfix-log.md`.
- Bug/root cause: static inspection found nested/secondary pages reachable from the compact shell still had shorter bottom padding than the floating 4-tab nav footprint. `NovelListPage` not-configured, loading/error, and list states used `24`/`20` bottom padding; `PluginTab` and `VideoSliverHome` used exactly `AppTokens.pageBottomPadding`, leaving little safety margin for phones with gesture/nav insets and the shell's rounded nav shadow.
- Fix: imported `AppTokens` into `novel_list_page.dart`, applied `AppTokens.pageBottomPadding + 32` to the novel not-configured/list/error states, and added the same +32 safety margin to plugin/video sliver endings.
- Verification output:
  - `dart format lib/novel/pages/novel_list_page.dart lib/plugin_tab.dart lib/video-Pro/pages/video_sliver_home.dart` → `Formatted 3 files (0 changed)`.
  - `flutter analyze` → `No issues found! (ran in 9.1s)`.
  - Web preview restart: initial start reported port 8080 already bound by this project's Flutter web-server; inspected process list and verified the existing project server was live.
  - `curl -sS -o /tmp/flutter_preview.html -w 'code=%{http_code} size=%{size_download}\n' http://127.0.0.1:8080/` → `code=200 size=1494`.
- Remaining risks: full tests were already green in Batch 1 and were not rerun for this layout-only padding change; next batch should target dialog/text overflow or a concrete async-context issue.

## 2026-06-08 22:00 local - Batch 3 dialog/sheet overflow hardening
- Files touched: `lib/update/update_dialog.dart`, `lib/video-Pro/pages/home/home_source_sheet.dart`, `lib/video-Pro/widgets/source_switch_sheet.dart`.
- Evidence/root cause: scanned dialog/sheet surfaces after analyzer was already clean. Update dialog used a non-scrollable `Column(mainAxisSize: min)` with large 30px title plus unbounded notice/changelog text; long release notes on small phones could overflow or push the update action off-screen. Home source picker sheet relied on `Flexible` inside a shrink-wrap column without an explicit viewport cap; large source lists or small screens could create bottom sheet sizing/overflow risk. Source switch sheet header and list titles did not cap long source names/actions.
- Fix: constrained update dialog to 86% screen height, moved release text into a scroll region, capped long title/notice/changelog text, and kept the update/progress action pinned below the scroll area. Added explicit max-height layout to the home source picker bottom sheet. Added ellipsis guards to source switch header action and source names.
- Verification: `dart format` completed for touched files; `flutter analyze` returned `No issues found!`.
- Remaining risks: run full tests and Web GET gate, then inspect history/delete dialogs and reader settings small-width chip row next.

## 2026-06-08 22:56 local — Batch 4 dialog overflow/resource cleanup
- Files touched: `lib/novel/pages/source_manager/book_source_manager_page.dart`, `lib/warehouse_tab.dart`, `.hermes/progress/long-ui-bugfix-log.md`.
- Bug/root cause: systematic dialog scan found active import/edit/add flows with tall fixed fields inside `AlertDialog`. The book-source import/editor dialogs used `TextField(maxLines: 16/18)` plus explanatory text without a screen-height cap, which can overflow on short phones or with keyboard/insets. Their `TextEditingController`s, plus the test-keyword controller, were not disposed after dialogs closed. The content-hub manual add dialog had scrollable form content but no explicit viewport cap, so dense text scale/small screens could still force actions off-screen.
- Fix: added 72%-screen-height constraints to book-source import/editor JSON dialogs, made the JSON text fields fill the capped body, disposed dialog controllers after await, and capped the warehouse manual-add dialog content height while preserving its scrollable form.
- Verification output:
  - `dart format lib/novel/pages/source_manager/book_source_manager_page.dart lib/warehouse_tab.dart` → `Formatted 2 files (1 changed)`.
  - `flutter analyze` → `No issues found! (ran in 12.8s)`.
  - Initially attempted non-existent targeted tests `test/novel_source_manager_test.dart test/warehouse_store_test.dart`; corrected by listing `test/` and running the relevant available smoke slice.
  - `flutter test test/smoke_test.dart` → `00:00 +1: All tests passed!`.
  - `git -c core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol diff --check` → clean. Plain `git diff --check` reports CRLF lines in `warehouse_tab.dart` as trailing-whitespace noise; the file is CRLF-formatted and analyzer/format are clean.
  - Restarted this project's Flutter web-server on port 8080 and verified `curl -sS -o /tmp/flutter_preview.html -w 'code=%{http_code} size=%{size_download}\n' http://127.0.0.1:8080/` → `code=200 size=1494`.
- Remaining risks: full `flutter test` was not rerun for this UI/layout-only batch; next batch should inspect async context/navigation flows in reader/source manager or long-label overflow in plugin market cards.
