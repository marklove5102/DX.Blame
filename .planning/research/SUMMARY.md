# Research Summary: DX.Blame v1.2 UX Polish & Settings

**Domain:** Delphi IDE plugin UX refinement and settings migration
**Researched:** 2026-03-26
**Overall confidence:** HIGH

## Executive Summary

The v1.2 milestone adds five UX features to the existing DX.Blame architecture. All five integrate cleanly with the current 28-unit codebase because they operate exclusively at the UI/UX layer -- no VCS logic, caching, or threading changes required.

The most architecturally significant change is the embedded IDE Options page (Feature 5), which introduces the INTAAddInOptions interface and requires extracting the settings UI from a modal TForm into a reusable TFrame. This is a well-documented OTA pattern used by GExperts, DDevExtensions, and other mature IDE plugins. The interface was verified in ToolsAPI.pas (Delphi 13) and requires 8 method implementations.

The statusbar display (Feature 2) is the most technically nuanced because it requires managing a TStatusPanel lifecycle across editor window creation/destruction. The INTAEditWindow.StatusBar property provides direct TStatusBar access, but the panel must be added/removed at the right moments.

Features 1 (annotation positioning), 3 (context menu toggle), and 4 (auto-scroll) are low-risk modifications to existing units with minimal code changes.

## Key Findings

**Stack:** No new dependencies. All features use existing ToolsAPI interfaces (INTAAddInOptions, INTAEditWindow.StatusBar, IOTAEditView.SetCursorPos/Center).

**Architecture:** 3 new units (Settings.Options, Settings.Frame, Statusbar) + 5 modified units. Clean separation: Frame is pure VCL, Options is thin OTA bridge, Statusbar is independent notifier.

**Critical pitfall:** INTAAddInOptions frame lifetime is IDE-managed. Frame must be stateless between dialog openings -- read from Settings singleton on create, write back on close.

## Implications for Roadmap

Based on research, suggested phase structure:

1. **Settings Foundation** - Add all new properties to TDXBlameSettings with INI persistence
   - Addresses: All 5 features need settings
   - Avoids: Dependent phases being blocked

2. **Annotation Positioning** - Modify Renderer.PaintLine X calculation
   - Addresses: Feature 1
   - Avoids: Scope creep (single method change)

3. **Context Menu & Auto-Scroll** - Modify Navigation unit
   - Addresses: Features 3 + 4
   - Avoids: Splitting two tightly coupled changes

4. **Settings Frame Extraction** - Create TFrame from existing TForm UI
   - Addresses: Feature 5 prerequisite
   - Avoids: Mixing OTA integration with UI layout

5. **IDE Options Integration** - Create INTAAddInOptions adapter, register
   - Addresses: Feature 5
   - Avoids: Frame extraction blocking OTA work

6. **Statusbar Display** - New INTAEditServicesNotifier for status bar updates
   - Addresses: Feature 2
   - Avoids: Complex notifier lifecycle mixed with simpler changes

7. **Integration & Polish** - Wire Registration, update dpk, update Tools menu
   - Addresses: All features unified
   - Avoids: Integration issues from incremental wiring

**Phase ordering rationale:**
- Settings first because all features depend on it
- Renderer and Navigation are independent, can be parallel
- Frame must precede Options (dependency)
- Statusbar is independent of Options, can be parallel with phases 4-5
- Registration last because it wires all new components

**Research flags for phases:**
- Phase 6 (Statusbar): May need deeper research on panel lifecycle across editor window create/destroy events
- Phases 1-5, 7: Standard patterns, unlikely to need additional research

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | No new dependencies, all ToolsAPI interfaces verified in source |
| Features | HIGH | All 5 features have clear integration points in existing code |
| Architecture | HIGH | INTAAddInOptions interface verified in ToolsAPI.pas line 6640; INTAEditWindow.StatusBar verified at line 2235 |
| Pitfalls | MEDIUM | Statusbar panel lifecycle across editor windows needs validation during implementation |

## Gaps to Address

- Statusbar panel persistence across editor window open/close needs empirical testing
- INTAEditServicesNotifier.EditorViewModified firing frequency under heavy editing should be validated (may need throttling)
- Whether IOTAEnvironmentOptions.EditOptions('', 'DX Blame') correctly navigates to the registered page needs runtime verification
