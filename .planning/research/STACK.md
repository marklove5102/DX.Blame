# Technology Stack

**Project:** DX.Blame v1.2 (UX Polish & Settings)
**Researched:** 2026-03-26

## Recommended Stack

No new external dependencies. All v1.2 features use existing Delphi RTL, VCL, and ToolsAPI interfaces already shipping in Delphi 11-13.

### Core Framework
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Delphi | 11/12/13 | IDE plugin host | Existing constraint, no change |
| Open Tools API | ToolsAPI.pas, ToolsAPI.Editor.pas | IDE integration | All 5 features use OTA interfaces available since Delphi 11+ |

### New OTA Interfaces for v1.2

#### 1. IDE Options Page (INTAAddInOptions)

| Interface | Unit | Purpose | Since |
|-----------|------|---------|-------|
| `INTAAddInOptions` | ToolsAPI.pas | Embed a TFrame as a page in Tools > Options dialog | Delphi XE+ |
| `INTAEnvironmentOptionsServices` | ToolsAPI.pas | Register/unregister the options page at plugin load/unload | Delphi XE+ |

**How it works:** Implement `INTAAddInOptions` on a class. `GetArea` returns `''` (places under "Third Party" node -- the recommended default). `GetCaption` returns `'DX Blame'`. `GetFrameClass` returns the TFrame class that contains settings controls. The IDE instantiates the frame; `FrameCreated` loads current settings into the frame. `DialogClosed(True)` saves settings. `ValidateContents` returns True (no validation needed beyond UpDown bounds). `IncludeInIDEInsight` returns True so users can find it via IDE Insight search.

**Registration pattern:**
```pascal
// In Register:
if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, LEnvOptions) then
  LEnvOptions.RegisterAddInOptions(GAddInOptions);

// In finalization:
if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, LEnvOptions) then
  LEnvOptions.UnregisterAddInOptions(GAddInOptions);
```

**Integration with existing code:** Extract the settings controls from `TFormDXBlameSettings` into a new `TFrameDXBlameSettings` (TCustomFrame descendant). The TForm keeps its controls but delegates to the frame for the actual UI. This avoids duplicating controls while supporting both the IDE Options page and a standalone dialog fallback.

**Verified:** Interface declaration confirmed in `ToolsAPI.pas` (Delphi 13 / Studio 37.0), lines 6640-6698. GUID: `{4B348F3E-6D01-4D88-A565-4C8C0EBF4335}`. Confidence: **HIGH**.

#### 2. Statusbar Display (INTAEditWindow.StatusBar)

| Interface | Unit | Purpose | Since |
|-----------|------|---------|-------|
| `INTAEditWindow.StatusBar` | ToolsAPI.pas | Access the editor window's TStatusBar for blame text display | Delphi 7+ |
| `INTAEditorServices` | ToolsAPI.pas | Enumerate edit windows and get TopEditWindow | Delphi 7+ |
| `INTAEditServicesNotifier.EditorViewModified` | ToolsAPI.pas | Notification when cursor moves -- trigger statusbar update | Delphi 7+ |

**How it works:** `INTAEditWindow.StatusBar` returns the native `Vcl.ComCtrls.TStatusBar` of the editor window. The status bar has multiple panels (line/col, modified state, insert mode). Add a new `TStatusPanel` to the end for blame text, or update the text of an existing panel.

**Recommended approach:** Add a new panel at runtime when the edit window is first accessed. Store the panel index. On each `EditorViewModified` callback, read the current line's blame data from cache and update the panel text. On `EditorViewActivated`, also update (handles tab switches). Remove the panel during cleanup.

**Key concern:** The IDE's statusbar panel layout is not formally documented. Adding a panel at runtime is safe -- the IDE does not expect a fixed panel count. But we must remove it cleanly on unload to prevent access violations.

**Integration with existing code:** The `INTAEditServicesNotifier` is already registered in `DX.Blame.IDE.Notifier` for cursor tracking. The statusbar update hooks into the same notifier callbacks -- no new notifier registration needed. The blame data lookup is identical to what the renderer does: `BlameEngine.Cache.TryGet` + line index.

**Verified:** Interface declaration confirmed in `ToolsAPI.pas` (Delphi 13), lines 2232-2241. `GetStatusBar: TStatusBar` returns VCL TStatusBar. Confidence: **HIGH**.

#### 3. Annotation X Positioning (Caret-Anchored)

| API | Unit | Purpose | Since |
|-----|------|---------|-------|
| `Context.EditorState.GetCharacterPosPx(Column, VisibleLine)` | ToolsAPI.Editor.pas | Get pixel rect for a specific character cell | Delphi 11 (280+) |
| `Context.LineState.VisibleTextRect` | ToolsAPI.Editor.pas | Get pixel rect of visible text on the line | Delphi 11 (280+) |
| `Context.CellSize` | ToolsAPI.Editor.pas | Character cell dimensions in pixels | Delphi 12 (290+) |
| `Context.EditView.CursorPos` | ToolsAPI.pas | Current caret position (Col, Line) | Delphi 7+ |
| `Context.EditorState.GetCodeLeftEdge` | ToolsAPI.Editor.pas | Pixel X where code area starts (after gutter) | Delphi 11 (280+) |

**Current implementation:** The renderer uses `Context.LineState.VisibleTextRect.Right + (Context.CellSize.cx * 3)` to position annotations after the last visible text character + 3 cell padding. This means annotations shift left/right depending on line length.

**Caret-anchored approach:** For "caret-anchored" positioning, use `Context.EditorState.GetCharacterPosPx(CaretCol, VisibleLine)` to get the pixel position of the caret column. This positions the annotation at a fixed X relative to the caret, not relative to each line's text end. For configurable fixed-column mode, use `GetCharacterPosPx(FixedColumn, VisibleLine)`.

**Three positioning modes to implement:**
1. **After text** (current behavior): `LineState.VisibleTextRect.Right + padding`
2. **At fixed column**: `EditorState.GetCharacterPosPx(ConfiguredColumn, VisibleLine).Left + padding`
3. **At caret column**: `EditorState.GetCharacterPosPx(CursorPos.Col, VisibleLine).Left + padding` (only meaningful in dsCurrentLine mode)

**Delphi 11 compatibility note:** `GetCharacterPosPx` is on `INTACodeEditorState280` (available since Delphi 11). `CellSize` is on `INTACodeEditorPaintContext290` (Delphi 12+). For Delphi 11, fall back to `EditorState.CharWidth` / `EditorState.CharHeight` from `INTACodeEditorState290`. But since the current code already uses `Context.CellSize`, Delphi 11 compatibility is already broken or handled -- check existing `{$IFDEF}` directives.

**Verified:** `GetCharacterPosPx(Column, VisibleLine): TRect` confirmed in `ToolsAPI.Editor.pas`, line 219, on `INTACodeEditorState280`. Confidence: **HIGH**.

#### 4. Context Menu Toggle with Shortcut Hint

| API | Unit | Purpose | Since |
|-----|------|---------|-------|
| `TPopupMenu.Items` (existing hook) | Vcl.Menus | Add toggle item to editor right-click menu | VCL (always) |
| `EditorLocalMenu` component | IDE internal | The editor's context popup menu | Delphi 7+ |

**No new OTA interface needed.** The existing `AttachContextMenu` in `DX.Blame.Navigation` already hooks the editor's `EditorLocalMenu` popup via `OnPopup` interception. Adding a "Toggle DX Blame" item with shortcut hint text follows the exact same pattern as the existing "Previous Revision" item.

**Implementation:** In the `OnEditorPopup` handler, add a new `TMenuItem` with:
- Caption: `'Toggle DX Blame'` + `#9` + `BlameSettings.ToggleHotkey` (Tab character before shortcut displays it right-aligned, standard Windows menu convention)
- Checked: `BlameSettings.Enabled`
- OnClick: Toggle enabled state, save, invalidate editors

**Integration with existing code:** Extends `TNavigationMenuHandler.OnEditorPopup` in `DX.Blame.Navigation`. No new notifier, no new hook -- just one more `TMenuItem.Create` in the existing popup handler.

**Verified:** Existing context menu hook confirmed working in `DX.Blame.Navigation.pas`. Confidence: **HIGH**.

#### 5. Auto-Scroll Historical Revision to Source Line

| Interface | Unit | Purpose | Since |
|-----------|------|---------|-------|
| `IOTAEditView40.SetCursorPos` | ToolsAPI.pas | Position cursor at specific line/column in opened file | Delphi 7+ |
| `IOTAEditView140.Center(Row, Col)` | ToolsAPI.pas | Scroll the view to center on specified row | Delphi 7+ |
| `IOTAActionServices.OpenFile` | ToolsAPI.pas | Open file in editor (already used) | Delphi 7+ |
| `IOTAEditorServices.TopView` | ToolsAPI.pas | Get the active edit view after opening | Delphi 7+ |

**Current implementation:** `NavigateToRevision` in `DX.Blame.Navigation` opens the temp file via `IOTAActionServices.OpenFile` but does not scroll to the source line.

**Scroll-to-line approach:** After `OpenFile`, retrieve the `IOTAEditorServices.TopView` for the newly opened file. Call `SetCursorPos` with the source line number (the line the user was on when they clicked "Previous Revision"), then call `Center(SourceLine, 1)` to scroll the view so the line is centered.

**Timing concern:** `OpenFile` may complete synchronously or the view may not be immediately available. Use `IOTAEditorServices.TopView` after `OpenFile` returns -- in practice this works because `OpenFile` is synchronous in the IDE and the top view is set before it returns. If the top view's buffer filename doesn't match the temp file, the open didn't complete -- handle gracefully.

**Integration with existing code:** `NavigateToRevision` already receives the source line context via `TryGetCurrentLineInfo`. Pass the line number through and add the scroll logic after the `OpenFile` call.

**Verified:** `SetCursorPos` on `IOTAEditView40` (line 1967), `Center(Row, Col)` on `IOTAEditView140` (line 2265) confirmed in `ToolsAPI.pas`. Confidence: **HIGH**.

### Existing OTA Interfaces (Unchanged from v1.0/v1.1)

| Interface | Purpose |
|-----------|---------|
| `INTACodeEditorEvents` / `INTACodeEditorEvents370` | Inline annotation painting and click detection |
| `IOTAKeyboardBinding` | Ctrl+Alt+B toggle shortcut |
| `IOTAIDENotifier` | File open/close/save events |
| `INTAEditServicesNotifier` | Cursor tracking, editor activation |
| `IOTAWizard` | Plugin registration |
| `IOTAAboutBoxServices` | About box entry |
| `INTACodeEditorServices` | Editor notifier registration, InvalidateTopEditor |

### Supporting Libraries (No Changes)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| System.IniFiles | RTL | Settings persistence | All settings read/write |
| System.Generics.Collections | RTL | Dictionary for hit-test data | Renderer annotation tracking |
| Vcl.ComCtrls | VCL | TStatusBar, TStatusPanel | Statusbar display feature |
| Vcl.Forms | VCL | TCustomFrame | Settings frame for IDE Options page |

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Status bar access | `INTAEditWindow.StatusBar` (add TStatusPanel) | `INTACustomEditorViewStatusPanel` | CustomEditorViewStatusPanel is for custom editor views (Design tab etc.), not the Code editor's existing status bar |
| Status bar updates | `INTAEditServicesNotifier.EditorViewModified` | TTimer polling | Polling wastes CPU and adds latency; EditorViewModified fires at exactly the right moments |
| Options page | `INTAAddInOptions` + TFrame | Keep modal TForm only | IDE Options is the standard location for plugin settings; users expect it there |
| Settings UI refactor | Extract TFrame, keep TForm as wrapper | Delete TForm entirely | TForm provides backward compatibility and direct access from menu during transition |
| X positioning | `GetCharacterPosPx` from EditorState | Manual `CellSize.cx * Column` calculation | GetCharacterPosPx handles proportional fonts and tabs correctly; manual calc does not |
| Scroll after open | `SetCursorPos` + `Center` | `SetTopPos` | Center is more user-friendly -- puts the line in the middle of the viewport, not at the top |
| Context menu toggle | Add to existing `OnEditorPopup` hook | Create a second popup hook | One hook is cleaner; existing pattern already proven stable |

## What NOT to Add

| Temptation | Why Avoid |
|------------|-----------|
| `IOTAEditorExplorerPersonalityTrait` | Only needed for custom editor personalities, not for blame display |
| `INTACustomEditorView` | For adding new tabs alongside Code/Design -- overkill for a statusbar panel |
| `IOTAProjectNotifier` | Already have `IOTAIDENotifier` for project switch detection |
| Custom dockable form for settings | INTAAddInOptions is the correct pattern for settings; dockable forms are for tool windows |
| `TActionList` / `TAction` for toggle | The existing TMenuItem.OnClick pattern in the context menu is simpler and sufficient |

## New Settings Properties Required

| Property | Type | Default | INI Key | Purpose |
|----------|------|---------|---------|---------|
| `AnnotationXMode` | `TDXBlameAnnotationXMode` (enum) | `axAfterText` | `[Format] AnnotationXMode` | Controls annotation horizontal positioning |
| `AnnotationFixedColumn` | Integer | 120 | `[Format] AnnotationFixedColumn` | Column number for fixed-column mode |
| `ShowInStatusBar` | Boolean | False | `[General] ShowInStatusBar` | Enable/disable statusbar blame display |

**New enum:**
```pascal
TDXBlameAnnotationXMode = (axAfterText, axAtFixedColumn, axAtCaretColumn);
```

## Installation

No new installation steps. The package remains a single BPL with no external dependencies.

```
Component > Install Packages > Add > DX.Blame.bpl
```

## Version Compatibility Matrix

| Feature | Delphi 11 (280) | Delphi 12 (290) | Delphi 13 (370) | Notes |
|---------|-----------------|-----------------|-----------------|-------|
| INTAAddInOptions | Yes | Yes | Yes | Available since XE |
| INTAEditWindow.StatusBar | Yes | Yes | Yes | Available since D7 |
| GetCharacterPosPx | Yes | Yes | Yes | INTACodeEditorState280 |
| IOTAEditView.Center | Yes | Yes | Yes | IOTAEditView140, available since D7 |
| Context menu hook | Yes | Yes | Yes | VCL TPopupMenu, always available |
| CellSize property | No (290+) | Yes | Yes | Fallback: EditorState.CharWidth/CharHeight |

**Action required:** Verify whether existing code already has a Delphi 11 fallback for `CellSize`. If not, add `{$IF CompilerVersion >= 34.0}` guard (Delphi 12 = 36.0, Delphi 11 = 35.0) or use runtime `Supports` check for `INTACodeEditorPaintContext290`.

## Sources

- `ToolsAPI.pas` (Delphi 13, Studio 37.0) -- verified all interface declarations, GUIDs, and inheritance chains
- `ToolsAPI.Editor.pas` (Delphi 13, Studio 37.0) -- verified paint context, line state, editor state interfaces
- Existing codebase: `DX.Blame.Renderer.pas`, `DX.Blame.Navigation.pas`, `DX.Blame.Registration.pas`, `DX.Blame.Settings.pas`, `DX.Blame.Settings.Form.pas`
- [Embarcadero OTAPI-Docs](https://github.com/Embarcadero/OTAPI-Docs)
- [GExperts OTA FAQ](https://www.gexperts.org/open-tools-api-faq/)
