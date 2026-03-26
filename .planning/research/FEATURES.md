# Feature Landscape: v1.2 UX Polish & Settings

**Domain:** Delphi IDE Plugin -- Blame annotation display, settings, and UX refinements
**Researched:** 2026-03-26
**Confidence:** HIGH (features modeled after GitLens/GitToolBox patterns, OTA APIs well-understood from v1.0/v1.1)

## Table Stakes

Features users expect from a mature blame annotation plugin. Missing = product feels incomplete compared to GitLens/GitToolBox.

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| Statusbar blame display | GitLens, GitToolBox, and VS Code built-in all show blame in statusbar. Users who find inline annotations noisy expect a quieter alternative. | Medium | Existing blame cache, cursor tracking via INTAEditServicesNotifier | Independent of inline -- both can be active simultaneously. Show author + relative time + short summary. Click opens commit popup. GitLens confirms: statusbar updates on every cursor movement, click opens action menu. Known concern: flicker during line changes while loading new blame data -- debounce or show previous value until new data ready. |
| Context menu toggle with shortcut hint | IntelliJ toggles blame from gutter right-click. GitLens has command palette toggle. Users expect toggle from the editor context, not buried in Tools menu. | Low | Existing OnEditorPopup hook in Navigation unit, existing toggle logic in Registration | Add "Enable/Disable Blame (Ctrl+Alt+B)" item. Checkmark state mirrors BlameSettings.Enabled. Trivial -- just another menu item in the existing popup hook. |
| Auto-scroll revision to source line | When navigating to a historical revision, opening at line 1 loses context. Every diff tool and blame tool scrolls to the relevant line. GitLens "Open Blame Prior to Change" preserves line position. | Low-Medium | Existing NavigateToRevision (DX.Blame.Navigation.pas line 27), IOTAEditView.SetCursorPos | Pass line number through NavigateToRevision. After OpenFile, obtain the new IOTAEditView and call SetCursorPos + Center. Timing may need a short delay for the editor to finish loading. |
| IDE Options page (INTAAddInOptions) | Professional IDE plugins register settings in Tools > Options, not standalone modal dialogs. GExperts, DelphiLSP, and other serious plugins all do this. Standalone Settings dialog feels amateur. | Medium | Existing TDXBlameSettings, new TFrame replacing TForm | Convert Settings.Form from TForm to TFrame. Implement INTAAddInOptions (GetFrameClass, GetCaption, GetArea, DialogClosed, FrameCreated, ValidateContents). Register via (BorlandIDEServices as INTAEnvironmentOptionsServices).RegisterAddInOptions. OTA docs confirm Chapter 36 covers this pattern. |

## Differentiators

Features that set DX.Blame apart. Not universally expected, but valued by power users.

| Feature | Value Proposition | Complexity | Dependencies | Notes |
|---------|-------------------|------------|--------------|-------|
| Caret-anchored annotation X positioning | Prevents horizontal jumping of annotations as user scrolls through lines of varying length. No other Delphi blame plugin offers this. GitLens places annotations at end-of-line and they jump; "Better Git Line Blame" extension also places at end-of-line. This is genuinely novel. | Medium | Existing PaintLine in Renderer (line 310-311), IOTAEditView.CursorPos for caret column, Context.CellSize.cx for character width | Compute X = max(CaretColumn * CellSize.cx + GutterWidth, VisibleTextRect.Right + 3*CellSize.cx). In all-lines mode, only caret line gets caret-anchored; other lines use end-of-line. When caret is before end-of-text, fall back to end-of-line + padding. |
| Dual display modes (inline + statusbar simultaneously) | GitLens allows both modes simultaneously. Most plugins force one or the other. Offering both independently is a power-user feature. | Low (once statusbar exists) | Statusbar feature, existing inline renderer | Two independent boolean settings: ShowInline, ShowStatusbar. Both default to true (inline) / false (statusbar). |
| Statusbar click opens commit popup | GitLens statusbar click opens a quick-pick menu with commit actions (compare, explore history). DX.Blame can reuse the existing popup panel for consistency -- simpler but effective. | Low | Statusbar feature, existing TDXBlamePopup | Reuse ShowForCommit with screen position near statusbar panel. |
| Remove Tools menu items after Options migration | Clean migration: once settings live in IDE Options, the Tools > DX.Blame menu becomes redundant. Removing it declutters the IDE. | Low | IDE Options page complete | Remove GMenuParentItem creation from Registration. Keep only Ctrl+Alt+B hotkey and context menu toggle. |

## Anti-Features

Features to explicitly NOT build for v1.2.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Configurable annotation format template (GitLens-style token system) | Over-engineering for a Delphi plugin with ~100 potential users. GitLens has ${author}, ${ago}, ${message} tokens -- massive implementation effort for marginal value. | Keep the existing ShowAuthor/DateFormat/ShowSummary/MaxLength checkboxes. Simple, discoverable, sufficient. |
| Hover tooltip on annotation (GitLens hover) | OTA does not provide reliable hover detection on custom-painted regions. Attempted and rejected in v1.0 design decisions. Click-to-popup works well. | Keep click-based popup. Already feels natural per v1.0 feedback. |
| Gutter-based blame column (IntelliJ style) | IntelliJ shows blame in a dedicated gutter column with colored bands. This requires PaintGutter integration, conflicts with existing line numbers/breakpoints, and is a completely different UX paradigm. | Keep end-of-line / caret-anchored inline annotations. This is the GitLens pattern users expect. |
| Annotation heatmap coloring (GitLens heatmap) | Color-coding annotations by age (red=recent, blue=old) adds visual complexity. Requires per-commit age calculation and color interpolation. Nice-to-have but not v1.2 scope. | Defer to v1.3+. Current theme-aware muted color works well. |
| Custom statusbar panel positioning (left/right alignment) | Delphi IDE statusbar panels are less flexible than VS Code. Adding alignment options adds complexity for minimal UX gain. | Place in a fixed position (rightmost custom panel). |
| Per-file or per-project settings | Some plugins allow different settings per project. This adds persistence complexity (project-level INI sections, discovery logic). | Keep global settings via %APPDATA%\DX.Blame\settings.ini. VCS preference already has per-project overrides where needed. |

## Feature Dependencies

```
IDE Options Page (TFrame) ──> Remove Tools Menu Items
                               (only after Options page works)

Statusbar Display ──> Statusbar Click Action
                       (click needs the panel to exist)

Caret-Anchored Positioning ──> (independent, renderer-only change)

Context Menu Toggle ──> (independent, extends existing popup hook)

Auto-Scroll Revision ──> (independent, extends NavigateToRevision)
```

## MVP Recommendation

### Phase 1: Quick wins (low complexity, high impact)
1. **Context menu toggle** -- 1-2 hours. Extends existing OnEditorPopup. Immediate UX improvement.
2. **Auto-scroll revision** -- 2-4 hours. Pass line number, SetCursorPos after open. Eliminates a real pain point.

### Phase 2: Display enhancements (medium complexity)
3. **Caret-anchored X positioning** -- 4-6 hours. Renderer-only change. Novel differentiator.
4. **Statusbar blame display** -- 6-8 hours. New statusbar panel, cursor tracking integration, click handler. Table stakes feature.

### Phase 3: Settings migration (medium complexity, lower urgency)
5. **IDE Options page** -- 6-8 hours. Convert TForm to TFrame, implement INTAAddInOptions, register. Professional polish.
6. **Remove Tools menu** -- 1 hour. Cleanup after Options page is verified working.

**Rationale:** Quick wins first to deliver immediate value. Display enhancements second because they affect daily UX. Settings migration last because the current standalone dialog works fine -- it is cosmetic polish, not a functional gap.

### Defer to v1.3+
- Annotation heatmap coloring
- Configurable format templates
- Per-project settings profiles

## Implementation Notes

### Annotation X Positioning (Caret-Anchored)

Current code (Renderer.pas line 310-311):
```pascal
LAnnotationX := Context.LineState.VisibleTextRect.Right +
  (Context.CellSize.cx * 3);
```

New logic should be:
```
if (line is caret line) and (caret column * CellSize.cx + padding > VisibleTextRect.Right):
  LAnnotationX := CaretColumn * CellSize.cx + GutterOffset + padding
else:
  LAnnotationX := VisibleTextRect.Right + padding  // fallback
```

Key consideration: In all-lines display mode (dsAllLines), only the caret line should use caret-anchored positioning. Other lines continue to use end-of-line positioning. This prevents ALL annotations from jumping when the caret moves.

New setting needed: `TDXBlameAnchorMode = (amEndOfLine, amCaretAnchored)` with amEndOfLine as default for backward compatibility.

### Statusbar Display

Two approaches to the Delphi IDE statusbar:

**Approach A (simpler): IOTAMessageServices**
- Use `(BorlandIDEServices as IOTAMessageServices).AddTitleMessage(Text)` to update the main statusbar text
- Pro: No component injection, clean OTA usage
- Con: Shares space with other IDE messages, may get overwritten by IDE actions

**Approach B (more control): Custom TStatusPanel injection**
- Access the IDE's TStatusBar via `(BorlandIDEServices as IOTAServices).GetMainForm` and find the TStatusBar component
- Create and inject a custom TStatusPanel with OnClick handler
- Pro: Dedicated space, click handling, not overwritten by IDE
- Con: Fragile -- relies on IDE internal component structure

**Recommendation:** Start with Approach B (custom panel). The dedicated space and click handler make it the better UX. The IDE's TStatusBar structure has been stable across Delphi 11-13.

**Update timing:** On every cursor movement (existing INTAEditServicesNotifier already tracks this). Debounce to avoid flicker -- GitLens has a known flicker issue when rapidly changing lines. Show previous blame data until new data is ready rather than clearing the statusbar.

Format: `"Author, relative-time -- summary"` (e.g., `"Olaf Monien, 3 days ago -- Fix cache invalidation"`)
Truncation: Total length capped at ~80 chars to prevent statusbar overflow.

### IDE Options Page (INTAAddInOptions)

Required interface methods:
- `GetFrameClass: TCustomFrameClass` -- return the TFrame descendant class
- `GetCaption: string` -- "DX.Blame" (appears in options tree)
- `GetArea: string` -- "Third Party" (standard area for plugins)
- `FrameCreated(AFrame: TCustomFrame)` -- populate controls from BlameSettings
- `DialogClosed(Accepted: Boolean)` -- if Accepted, save to BlameSettings and call Save
- `ValidateContents: Boolean` -- return True (no complex validation needed)
- `IncludeInIDEInsight: Boolean` -- return True for searchability
- `GetHelpContext: Integer` -- return 0 (no help file)

Registration: `(BorlandIDEServices as INTAEnvironmentOptionsServices).RegisterAddInOptions(TDXBlameAddInOptions.Create)`
Cleanup: Store the instance and call `UnregisterAddInOptions` during finalization.

The existing Settings.Form.pas TForm layout can be reused almost entirely -- convert to TFrame, remove OK/Cancel buttons (the IDE Options dialog provides those), wire up FrameCreated/DialogClosed for load/save.

**Important:** The new settings TFrame must also accommodate the two new settings added by v1.2 features:
- `AnchorMode: TDXBlameAnchorMode` (amEndOfLine / amCaretAnchored)
- `ShowStatusbar: Boolean` (independent of ShowInline)

### Context Menu Toggle

Add to `TNavigationMenuHandler.OnEditorPopup`:
```
- Separator
- "Enable Blame (Ctrl+Alt+B)" with checkmark = BlameSettings.Enabled
  OnClick: toggle BlameSettings.Enabled, Save, InvalidateAllEditors, SyncEnableBlameCheckmark
```

Place BEFORE the existing "Show revision..." item for logical grouping (toggle first, then actions).

### Auto-Scroll Revision

Modify `NavigateToRevision` signature (DX.Blame.Navigation.pas line 27) to accept `ALineNumber: Integer`:
```pascal
procedure NavigateToRevision(const AFileName, ACommitHash, ARepoRoot: string;
  ALineNumber: Integer = 1);
```

After `LActionServices.OpenFile(LTempFile)`:
1. Get `IOTAEditorServices.TopView`
2. Call `TopView.SetCursorPos(EditorPos(1, ALineNumber))`
3. Call `TopView.Center(ALineNumber, 1)` to center the line on screen
4. May need `Application.ProcessMessages` or a short timer if the editor has not finished loading

The caller (context menu handler at line 216) already knows the logical line from LLineInfo -- just pass it through.

## Sources

- [GitLens Settings Documentation](https://help.gitkraken.com/gitlens/gitlens-settings/) -- MEDIUM confidence (verified against official docs)
- [GitLens Core Features](https://help.gitkraken.com/gitlens/gitlens-features/) -- MEDIUM confidence
- [GitLens Custom Formatting Tokens](https://github.com/gitkraken/vscode-gitlens/wiki/Custom-Formatting) -- HIGH confidence (official wiki)
- [GitLens Statusbar Flicker Issue](https://github.com/gitkraken/vscode-gitlens/issues/272) -- HIGH confidence (direct issue report)
- [GitToolBox Blame Display](https://gittoolbox.lukasz-zielinski.com/docs/git-blame-display/) -- MEDIUM confidence
- [Better Git Line Blame Extension](https://marketplace.visualstudio.com/items?itemName=mk12.better-git-line-blame) -- MEDIUM confidence
- [IntelliJ IDEA Git Blame Documentation](https://www.jetbrains.com/help/idea/investigate-changes.html) -- HIGH confidence (official JetBrains docs)
- [Embarcadero OTA Documentation](https://github.com/Embarcadero/OTAPI-Docs/blob/main/The%20Delphi%20IDE%20Open%20Tools%20API%20-%20Version%201.2.md) -- HIGH confidence (official Embarcadero, Chapter 36 covers Options pages)
- [GExperts Open Tools API FAQ](https://www.gexperts.org/open-tools-api-faq/) -- HIGH confidence (established OTA reference)
- Existing DX.Blame v1.0/v1.1 codebase -- HIGH confidence (direct source inspection, verified line references)
