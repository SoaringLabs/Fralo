# Fralo localization

The production macOS interface, shared controls, and core errors support English (`en`), Simplified Chinese (`zh-Hans`), Traditional Chinese (`zh-Hant`), and Japanese (`ja`). The app follows macOS preferred languages, including the language selected for Fralo in System Settings → General → Language & Region → Applications. Quit and reopen Fralo after changing the language. English is the fallback for unsupported languages.

## Add or change text

1. Import `FraloLocalization` and put the complete sentence in `L10n.tr`, including accessibility labels and hints:

   ```swift
   L10n.tr("正在处理：\(filename)")
   ```

2. Add the key `正在处理：{0}` to all four files under `Sources/FraloLocalization/Resources/<language>.lproj/Localizable.strings`. The existing Simplified Chinese wording is the stable lookup key; a new English key also works. Update every call site and language if a key changes. Numbered placeholders may move to match grammar, but each must occur the same number of times. Avoid sentence fragments and English singular/plural suffixes; use count-neutral English where possible (for example `Images: {0}`).
3. Keep filenames and other user data inside interpolation. The renderer substitutes arguments once, so text such as `{1}` in a filename stays untouched. Technical identifiers, persistence keys, command flags, format names, and brand names are language independent. Do not translate them.
4. Run the completeness checker and its negative-path tests:

   ```sh
   python3 -B scripts/check_localizations.py
   python3 -B scripts/test_check_localizations.py
   swift test --build-system native
   ```

The checker validates all four catalogs, duplicate/empty entries, source registrations, numbered arguments, and existing printf filename formats. It rejects untranslated CJK text and common English UI literal call sites in production Swift sources. This is a guardrail, not a full Swift type checker: review new UI factories and dynamically constructed text too. Development-only Design Lab samples and the standalone CLI help/argument interface are outside the production UI catalog check.

## Resources and packaging

`FraloLocalization` owns a SwiftPM resource bundle shared by App, Core, and DesignSystem. SwiftPM lowercases localization directories in its build output, so the loader resolves those names explicitly. The loader resolves app, test and executable-relative resource paths without a generated absolute build-path dependency. A copied standalone CLI without catalogs keeps its original source-language errors instead of crashing. Signed apps must copy `Fralo_FraloLocalization.bundle` into `Contents/Resources` and declare all four `CFBundleLocalizations`; both preview scripts and `scripts/package.py` do this. Do not depend on a source-tree or build-directory resource fallback in a packaged app.

## Preview and visual review

Launch previews through the repository script so it builds successfully before handing over from older previews in every worktree:

```sh
scripts/run-workbench-preview.sh --preview-language=ja --preview-window=1030x640 --preview-appearance=light
```

`--preview-language` is a Debug-only Workbench Preview override; it does not change user settings. Check all four languages, empty and populated states, menus, Settings, disabled controls, long error messages, and keyboard focus in light/dark appearance at minimum and normal sizes. Labels should wrap or controls should reflow before clipping their meaning. VoiceOver labels and help are translated; screenshots and automated checks do not establish full VoiceOver compliance.

## FRALO-35 verification

The text and adaptive layout changes follow Apple HIG [Writing](https://developer.apple.com/design/human-interface-guidelines/writing) (clear, consistent, localizable language) and [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) (adapt to translated text length). Existing AppKit controls, appearance choices, shortcuts, and selection behavior are retained. Long option labels reflow rather than shrinking the text.

On the development Mac, all four languages were launched and their workspaces and Settings checked. Selected combinations covered light/dark appearance, 1030×640 and 1200×780 windows, empty and populated batches, English/Japanese menus, English Settings arrow-key selection, and Tab from the image list to the canvas. English background/composition/export labels and Japanese empty-state/device labels were inspected after their clipping fixes.

Automated validation passed: 175 Swift tests (two existing opt-in desktop/performance probes skipped), seven localization guard tests, all 254 keys in four catalogs, Debug and Release builds, existing CLI integration checks, and a copied standalone CLI returning a normal corrupt-image failure without a translation bundle. Update-feed and preview-process tests also passed.

Not verified: the actual macOS per-app language-setting screen, the full VoiceOver flow, every language/state/accessibility-option combination, or runtime behavior on older supported macOS versions. Language negotiation and resource-bundle relocation are covered by automated tests; these do not replace those manual checks.
