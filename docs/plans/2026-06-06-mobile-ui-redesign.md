# Flutter Mobile UI Redesign Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Redesign the existing Flutter app into a modern mobile-first content/tool hub with clear bottom navigation, reusable design system, polished Home/Video/Novel/Tools/Profile flows, and improved touch ergonomics.

**Architecture:** Introduce a small in-app design system first, then rebuild the app shell around five user-facing tabs: Home, Video, Novel, Tools, Profile. Preserve existing business logic and controllers where possible; move only UI composition and shared widgets first to reduce regression risk.

**Tech Stack:** Flutter Material 3, Provider, existing `video-Pro`, `novel`, `plugin`, `warehouse`, `update`, and logging modules.

---

## Product Direction

Use this visual direction across the app:

- Light, modern, mobile-first.
- Rounded cards, soft shadows, generous spacing.
- Content-first layouts for Video and Novel.
- Efficiency-first layouts for Tools, Plugins, Resource Library, and Settings.
- Blue/purple accent system with warm secondary accents.
- Avoid old “icon wall” / demo-style Flutter pages.

Target bottom navigation:

```text
首页 / 视频 / 小说 / 工具 / 我的
```

Mapping existing features:

| Existing Feature | New Destination |
|---|---|
| `HomePage` | Home tab |
| `VideoListPage` / `video-Pro` pages | Video tab |
| Novel pages | Novel tab |
| `ToolPage` | Tools tab |
| `PluginTab`, `PluginMarketPage` | Tools tab and Profile management entry |
| `WarehouseTab` | Tools tab as “资源库” |
| `DebugLogPage` | Profile > Debug Logs |
| Update check | Startup bootstrap + Profile > Check Update |

---

# Phase 0: Safety fixes before major UI work

These are not UI tasks, but they prevent false failures while redesigning.

## Task 0.1: Fix novel controller compile error

**Objective:** Make `flutter analyze` free of P0 undefined identifier errors before UI refactors.

**Files:**
- Modify: `lib/novel/controllers/novel_list_controller.dart`

**Change:**

Replace inside `_resolvePrimaryExploreEntry`:

```dart
final source = _ruleSource;
if (source == null) return null;

final raw = source.exploreUrl.trim();
```

with:

```dart
final source = _activeSource;
if (source == null) return null;

final raw = _exploreUrlOf(source).trim();
```

**Verify:**

```bash
flutter analyze
```

Expected: no `Undefined name '_ruleSource'` error.

---

## Task 0.2: Remove generated APK artifacts from `lib/`

**Objective:** Prevent generated release artifacts from polluting source and analyzer scope.

**Files:**
- Move/remove: `lib/utils/flutter-apk/`
- Modify: `.gitignore`

**Steps:**

1. If these APKs are not needed, remove the directory:

```bash
rm -rf lib/utils/flutter-apk
```

2. Add to `.gitignore`:

```gitignore
*.apk
*.sha1
artifacts/
dist/
release/
```

**Verify:**

```bash
find lib -iname '*.apk' -o -iname '*.sha1'
flutter analyze
```

Expected: no APK/SHA files under `lib/`.

---

## Task 0.3: Restrict insecure certificate override to debug builds

**Objective:** Prevent release builds from globally accepting bad HTTPS certificates.

**Files:**
- Modify: `lib/main.dart`

**Change:**

Replace:

```dart
enableInsecureCertificateOverrides();
```

with:

```dart
if (kDebugMode) {
  enableInsecureCertificateOverrides();
}
```

`kDebugMode` is already imported from `package:flutter/foundation.dart`.

**Verify:**

```bash
flutter analyze
```

Expected: no new errors.

---

# Phase 1: Design system foundation

## Task 1.1: Create design token files

**Objective:** Centralize colors, spacing, radius, shadows, and typography.

**Files:**
- Create: `lib/design/app_colors.dart`
- Create: `lib/design/app_spacing.dart`
- Create: `lib/design/app_radius.dart`
- Create: `lib/design/app_shadows.dart`
- Create: `lib/design/app_text_styles.dart`

**Implementation notes:**

Use this palette:

```text
Primary: #3B82F6
Secondary: #8B5CF6
Success: #22C55E
Warning: #F59E0B
Danger: #EF4444
Background: #F7F8FA
Surface: #FFFFFF
Text primary: #111827
Text secondary: #6B7280
Text tertiary: #9CA3AF
Border: #E5E7EB
```

Dark-mode tokens should be present even if not activated immediately:

```text
Dark background: #0B0F19
Dark surface: #111827
Dark elevated surface: #1F2937
Dark text primary: #F9FAFB
Dark text secondary: #9CA3AF
```

**Verify:**

```bash
flutter analyze
```

---

## Task 1.2: Create Material 3 app theme

**Objective:** Provide a consistent app-wide theme.

**Files:**
- Create: `lib/design/app_theme.dart`
- Modify: `lib/main.dart` or future `lib/app/app.dart`

**Theme requirements:**

- `useMaterial3: true`
- Seed color blue/purple.
- `scaffoldBackgroundColor: AppColors.background`
- Rounded `CardThemeData`.
- Rounded `BottomSheetThemeData`.
- Consistent `InputDecorationTheme` for search boxes.
- Button radius 14-16.

**Verify:**

Run the app and inspect Home, Video, Novel, Tools pages for no visual breakage.

---

## Task 1.3: Create common UI widgets

**Objective:** Build reusable components before rewriting screens.

**Files:**
- Create directory: `lib/widgets/common/`
- Create: `lib/widgets/common/app_card.dart`
- Create: `lib/widgets/common/app_search_bar.dart`
- Create: `lib/widgets/common/app_section_header.dart`
- Create: `lib/widgets/common/app_empty_state.dart`
- Create: `lib/widgets/common/app_error_state.dart`
- Create: `lib/widgets/common/app_badge.dart`
- Create: `lib/widgets/common/app_icon_tile.dart`
- Create: `lib/widgets/common/app_primary_button.dart`
- Create: `lib/widgets/common/app_bottom_sheet.dart`

**Component behavior:**

- Minimum tap target: 44 x 44 dp.
- All cards use consistent padding and radius.
- Empty/error states include icon, title, description, optional action button.
- Search bar is read-only or editable depending on caller.

**Verify:**

```bash
flutter analyze
```

---

# Phase 2: New app shell and navigation

## Task 2.1: Create app shell files

**Objective:** Move UI shell out of `main.dart` and prepare clean five-tab layout.

**Files:**
- Create: `lib/app/app.dart`
- Create: `lib/app/app_shell.dart`
- Create: `lib/app/app_routes.dart`
- Create: `lib/app/app_providers.dart`
- Modify: `lib/main.dart`

**Architecture:**

`main.dart` should keep initialization only:

- `WidgetsFlutterBinding.ensureInitialized()`
- debug-only certificate override
- `Hive.initFlutter()`
- logger init
- error handlers
- SharedPreferences
- novel bootstrap
- video module config
- `runApp(App(...))`

`App` owns `MaterialApp`.

`AppShell` owns bottom navigation and page switching.

**Verify:**

```bash
flutter analyze
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
```

---

## Task 2.2: Replace bottom navigation with five user-facing tabs

**Objective:** Change bottom nav to Home / Video / Novel / Tools / Profile.

**Files:**
- Modify: `lib/app/app_shell.dart`
- Create: `lib/profile/profile_page.dart`
- Keep/route existing pages:
  - `lib/home_page.dart`
  - `lib/video_module.dart` or `lib/video-Pro/video_module.dart`
  - `lib/novel/pages/novel_list_page.dart`
  - `lib/tool_page.dart`

**Navigation labels:**

```text
首页 Icons.home_rounded
视频 Icons.smart_display_rounded
小说 Icons.menu_book_rounded
工具 Icons.grid_view_rounded
我的 Icons.person_rounded
```

**UX requirements:**

- Use `NavigationBar` or a custom rounded bottom navigation.
- Preserve page state with `PageView` or `IndexedStack`.
- Avoid animation conflicts with nested tabs.

**Verify:**

Switch all five tabs repeatedly; state should not reset unnecessarily.

---

# Phase 3: Home redesign

## Task 3.1: Split Home page into smaller widgets

**Objective:** Replace the old large HomePage with composable mobile-first sections.

**Files:**
- Create directory: `lib/home/`
- Create: `lib/home/home_page.dart`
- Create: `lib/home/widgets/home_header.dart`
- Create: `lib/home/widgets/home_global_search_card.dart`
- Create: `lib/home/widgets/home_continue_card.dart`
- Create: `lib/home/widgets/home_quick_actions.dart`
- Create: `lib/home/widgets/home_recent_section.dart`
- Modify imports from old `lib/home_page.dart` to new page.

**Home layout:**

```text
SafeArea
  CustomScrollView
    HomeHeader
    GlobalSearchCard
    ContinueCard
    QuickActions
    RecentSection
```

**Visual requirements:**

- App title: `Geek 工具箱`.
- Subtitle: dynamic greeting or short slogan.
- Search placeholder: `搜影视 / 小说 / 工具 / 插件`.
- Continue card prioritizes recently watched/read content if available; fallback to feature tips.
- Quick actions: 视频、小说、工具、插件、资源库、日志.

**Verify:**

Home should fit one-handed phone operation and not feel like a dense icon wall.

---

## Task 3.2: Replace mock daily news with useful home status

**Objective:** Remove fake news as primary homepage content.

**Files:**
- Modify: `lib/home/home_page.dart`
- Optionally keep: `lib/daily_news_page.dart` as a separate tool entry if still wanted.

**New status card content:**

- Continue watching.
- Continue reading.
- Current video source.
- Current novel source.
- App update hint if available.

**Fallback if no data:**

Show a polished onboarding card:

```text
开始探索
导入书源、切换视频源，或者打开工具箱。
[去看视频] [找小说]
```

---

# Phase 4: Video UI redesign

## Task 4.1: Redesign Video home header and source selector

**Objective:** Make video page feel like a lightweight streaming app.

**Files:**
- Modify: `lib/video-Pro/pages/video_sliver_home.dart`
- Modify/reuse: `lib/video-Pro/pages/home/home_header_section.dart`
- Modify/reuse: `lib/video-Pro/pages/home/home_source_sheet.dart`

**UI requirements:**

- Top title: `视频`.
- Search icon/button.
- Source chip showing current source.
- Source status: available / loading / failed.
- Horizontal category chips.

**Verify:**

Source switching should still call existing `VideoController` logic.

---

## Task 4.2: Modernize video poster grid

**Objective:** Replace dense list/grid with modern 2-column poster cards.

**Files:**
- Modify: `lib/video-Pro/pages/home/home_video_grid.dart`
- Create/reuse: `lib/video-Pro/widgets/video_poster_card.dart`

**Card content:**

- Poster image, 2:3 ratio.
- HD/update badge.
- Title max 2 lines.
- Subtitle: type/year/update status.
- Error placeholder for missing poster.

**Performance:**

- Use `CachedNetworkImage` already in dependencies.
- Use consistent `memCacheWidth` if possible.
- Use skeleton placeholder while loading.

---

## Task 4.3: Redesign video detail page

**Objective:** Make detail page visually rich and mobile-friendly.

**Files:**
- Modify: `lib/video-Pro/pages/video_detail_page.dart`
- Modify/reuse detail widgets under `lib/video-Pro/pages/detail/`

**Layout:**

```text
Header poster backdrop with gradient
Poster + title + metadata
Primary play button
Synopsis expandable section
Line selector
Episode section
Related/recommendations placeholder
```

**Verify:**

- Episode switching still works.
- Play button opens existing player.
- Long titles and missing images are handled.

---

# Phase 5: Novel UI redesign

## Task 5.1: Redesign novel home/list page

**Objective:** Turn novel page into a reader-style home with search, bookshelf, and discovery.

**Files:**
- Modify: `lib/novel/pages/novel_list_page.dart`
- Create: `lib/novel/widgets/novel_source_status_card.dart`
- Create: `lib/novel/widgets/novel_book_card.dart`
- Create: `lib/novel/widgets/novel_bookshelf_section.dart`

**Layout:**

```text
Top: 小说 title + 书源管理 button
Search bar
Current source status card
Recently reading / bookshelf section
Discover/search results list
```

**UX:**

- Source management is in the top-right; do not interrupt normal reading.
- Empty source state should show `导入书源` action.
- Search results should support loading/error/empty states.

---

## Task 5.2: Redesign novel detail page

**Objective:** Make book detail page look like a real reading app.

**Files:**
- Modify: `lib/novel/pages/novel_detail_page.dart`

**Layout:**

```text
Cover + title + author
Tags: status/source/latest
Synopsis expandable
Buttons: 开始阅读 / 加入书架
Latest chapter
Directory entry
```

**Verify:**

- Existing continue/read flow still works.
- Bookshelf manager integration still works.

---

## Task 5.3: Modernize reader settings and overlays

**Objective:** Improve pure reading experience on phone.

**Files:**
- Modify: `lib/novel/pages/reader_page.dart`
- Modify: `lib/novel/pages/reader/reader_top_bar.dart`
- Modify: `lib/novel/pages/reader/reader_bottom_bar.dart`
- Modify: `lib/novel/pages/reader/reader_settings_sheet.dart`
- Modify: `lib/novel/pages/reader/reader_directory_sheet.dart`

**Reader requirements:**

- Tap center to show/hide controls.
- Top overlay: back, book title, more.
- Bottom overlay: directory, progress, font, theme, page mode.
- Themes: white, paper, eye-care, dark.
- Font size controls: A- / A+.
- Line height controls.
- Respect SafeArea.

---

# Phase 6: Tools, plugins, resource library, profile

## Task 6.1: Redesign Tools page as categorized tool hub

**Objective:** Replace icon wall with search + recent + categories.

**Files:**
- Modify: `lib/tool_page.dart`
- Create: `lib/tools/widgets/tool_action_card.dart`
- Create: `lib/tools/widgets/tool_category_section.dart`

**Sections:**

- Search tools.
- Recently used.
- Content tools.
- Network tools.
- Developer tools.
- System tools.
- Entries for Plugin Market and Resource Library.

---

## Task 6.2: Redesign plugin market cards

**Objective:** Make plugin UI look like an extension store.

**Files:**
- Modify: `lib/plugin_tab.dart`
- Modify: `lib/plugin_market_page.dart`
- Create: `lib/plugins/widgets/plugin_card.dart`
- Create: `lib/plugins/widgets/plugin_security_badge.dart`

**Plugin card content:**

- Icon.
- Name.
- Author/version.
- Description.
- Status: installed / update available / install.
- Security: signed / source verified / permissions.

---

## Task 6.3: Redesign resource library / warehouse

**Objective:** Rename and style warehouse as mobile resource library.

**Files:**
- Modify: `lib/warehouse_tab.dart`

**UI requirements:**

- Title: `资源库`.
- Search and filter chips.
- File/resource list with icon, size, updated time.
- Swipe/long-press actions: share, delete, details.

---

## Task 6.4: Build Profile page

**Objective:** Add a clean management center.

**Files:**
- Create/modify: `lib/profile/profile_page.dart`
- Create: `lib/profile/settings_page.dart`
- Create: `lib/profile/cache_page.dart`

**Profile content:**

- App name and version.
- Status card: video source, novel source, plugin count, cache estimate.
- Settings list:
  - Check update.
  - Plugin management.
  - Book source management.
  - Video source management.
  - Cache cleanup.
  - Debug logs.
  - About.

---

# Phase 7: Global search

## Task 7.1: Add unified search page

**Objective:** Provide one search entry for video, novel, tools, and plugins.

**Files:**
- Create: `lib/search/global_search_page.dart`
- Create: `lib/search/widgets/search_type_tabs.dart`
- Create: `lib/search/widgets/search_history_section.dart`
- Create: `lib/search/widgets/global_search_results.dart`

**Search tabs:**

```text
全部 / 视频 / 小说 / 工具 / 插件
```

**Behavior:**

- Home search opens this page.
- Video and Novel results can call existing search logic.
- Tools/plugins can be local filtered first.

---

# Phase 8: Polish and verification

## Task 8.1: Replace deprecated `withOpacity` gradually

**Objective:** Reduce analyzer noise and align with current Flutter.

**Files:**
- Multiple UI files.

**Rule:**

Replace:

```dart
color.withOpacity(0.12)
```

with:

```dart
color.withValues(alpha: 0.12)
```

**Verify:**

```bash
flutter analyze
```

---

## Task 8.2: Fix async context warnings touched by UI work

**Objective:** Prevent navigation/snackbar crashes after async gaps.

**Files:**
- Any modified UI files that show `use_build_context_synchronously`.

**Rule:**

After `await`, before using `context`:

```dart
if (!mounted) return;
```

For a passed `BuildContext`:

```dart
if (!context.mounted) return;
```

Do not guard one context with an unrelated `mounted` check.

---

## Task 8.3: Run verification suite

**Objective:** Confirm redesigned UI still builds.

**Commands:**

```bash
export JAVA_HOME=/c/tools/jdk17/jdk-17.0.19+10
export ANDROID_SDK_ROOT=/c/Android/Sdk
export ANDROID_HOME=/c/Android/Sdk
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export PATH="/c/tools/flutter-sdk/flutter/bin:$JAVA_HOME/bin:/c/Android/Sdk/cmdline-tools/latest/bin:/c/Android/Sdk/platform-tools:$PATH"

flutter pub get
flutter analyze
flutter build apk --debug
```

Expected:

- No analyzer errors.
- Warnings/info can remain initially but should trend down.
- Debug APK builds successfully.

---

# Implementation Order Summary

1. Fix P0 compile/source hygiene issues.
2. Add design tokens and common widgets.
3. Create new app shell with five bottom tabs.
4. Redesign Home.
5. Redesign Video home/detail/player controls.
6. Redesign Novel home/detail/reader.
7. Redesign Tools/Plugin/Resource Library.
8. Add Profile and global search.
9. Polish analyzer warnings and verify APK build.

---

# Acceptance Criteria

The redesign is successful when:

- App opens into a modern Home page, not a dense demo-style list.
- Bottom navigation is `首页 / 视频 / 小说 / 工具 / 我的`.
- Video feels like a lightweight streaming app.
- Novel feels like a reading app with clean reader controls.
- Tools and plugins are categorized and searchable.
- Settings/debug/update/cache management are moved into Profile.
- Common visual language is consistent across screens.
- Main tap targets are mobile-friendly.
- `flutter analyze` has no hard errors.
- Debug APK builds successfully.
