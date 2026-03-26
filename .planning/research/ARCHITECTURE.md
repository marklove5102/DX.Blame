# Architecture Patterns

**Domain:** UX Polish & Settings integration for DX.Blame Delphi IDE plugin (v1.2)
**Researched:** 2026-03-26

## Recommended Architecture

Five features integrate into the existing 28-unit architecture. Three require new units, all five modify existing units. No new OTA interfaces beyond what Delphi 11+ already provides.

### Component Map

```
+-------------------+     +---------------------+     +-------------------+
| DX.Blame          |     | DX.Blame            |     | DX.Blame          |
| .Settings         |<----| .Settings.Options   |---->| .Settings.Frame   |
| (singleton, INI)  |     | (INTAAddInOptions)  |     | (TFrame for IDE)  |
+-------------------+     +---------------------+     +-------------------+
        ^                                                     |
        |  reads/writes                                       | replaces
        |                                                     v
+-------------------+     +---------------------+     +-------------------+
| DX.Blame          |     | DX.Blame            |     | DX.Blame          |
| .Renderer         |     | .Statusbar          |     | .Settings.Form    |
| (inline paint)    |     | (statusbar display) |     | (modal dialog)    |
+-------------------+     +---------------------+     | KEEP for fallback |
        |                         ^                   +-------------------+
        | uses settings           | uses settings
        v                         |
+-------------------+     +---------------------+
| DX.Blame          |     | DX.Blame            |
| .Navigation       |     | .Registration       |
| (context menu,    |     | (lifecycle, menu,   |
|  auto-scroll)     |     |  options reg)       |
+-------------------+     +---------------------+
```

### New Units (3)

| Unit | Type | Responsibility | Depends On |
|------|------|---------------|------------|
| `DX.Blame.Settings.Options` | Class (INTAAddInOptions) | Implements INTAAddInOptions to register the options frame with IDE Tools > Options dialog. Bridges between IDE lifecycle and TFrame. | Settings, Settings.Frame, ToolsAPI |
| `DX.Blame.Settings.Frame` | TFrame | The actual UI for IDE Options page -- identical controls to current Settings.Form but as TFrame, not TForm. LoadFromSettings/SaveToSettings methods. | Settings, Renderer (for InvalidateAllEditors) |
| `DX.Blame.Statusbar` | Class | Reads blame data for current line and writes to INTAEditWindow.StatusBar. Updates on cursor movement via INTAEditServicesNotifier or timer. | Settings, Engine, Cache, Formatter, VCS.Types, ToolsAPI |

### Modified Units (5)

| Unit | What Changes | Why |
|------|-------------|-----|
| `DX.Blame.Settings` | Add 3 new properties: `AnnotationPosition` (enum: apEndOfLine/apCaretColumn), `StatusbarEnabled` (Boolean), `DisplayMode` (enum: dmInline/dmStatusbar/dmBoth). Persist to INI. | All 5 features need settings. Statusbar is independent of inline -- both can run simultaneously. |
| `DX.Blame.Renderer` | Modify PaintLine X-position calculation to use caret column when `AnnotationPosition = apCaretColumn`. Skip painting when `DisplayMode = dmStatusbar` (statusbar-only mode). | Feature 1 (annotation positioning) and Feature 2 (statusbar mode). |
| `DX.Blame.Navigation` | Add "Enable Blame (Ctrl+Alt+B)" toggle item to OnEditorPopup. Pass line number through NavigateToRevision and scroll opened temp file to that line. | Feature 3 (context menu toggle) and Feature 4 (auto-scroll). |
| `DX.Blame.Registration` | Register/unregister INTAAddInOptions via INTAEnvironmentOptionsServices. Register/unregister DX.Blame.Statusbar notifier. Optionally remove Tools > DX Blame menu (or keep as secondary access). | Feature 5 (embedded Options page) and Feature 2 (statusbar lifecycle). |
| `DX.Blame.dpk` | Add 3 new units to `contains` clause. | Package must list all units. |

### Unchanged Units

All VCS units (Git.*, Hg.*, VCS.*), Cache, Engine, Formatter, CommitDetail, Popup, Diff.Form, KeyBinding, IDE.Notifier, Version remain untouched. This milestone is purely UI/UX layer.

## Feature Integration Details

### Feature 1: Annotation X Positioning

**What:** Anchor inline annotation to the caret column instead of end-of-line.

**Integration point:** `TDXBlameRenderer.PaintLine` -- the `LAnnotationX` calculation (line ~310 of Renderer.pas).

**Current behavior:**
```pascal
LAnnotationX := Context.LineState.VisibleTextRect.Right +
  (Context.CellSize.cx * 3);
```

**New behavior (when apCaretColumn):**
```pascal
// Compute caret-anchored X: caret column * cell width + gutter offset + padding
LCaretX := (Context.EditView.CursorPos.Col - 1) * Context.CellSize.cx +
  Context.LineState.VisibleTextRect.Left;
LEndOfLineX := Context.LineState.VisibleTextRect.Right +
  (Context.CellSize.cx * 3);
// Use caret position, but never earlier than end-of-line
LAnnotationX := Max(LCaretX + (Context.CellSize.cx * 3), LEndOfLineX);
```

**Fallback rules:** Use end-of-line when:
- DisplayScope = dsAllLines (caret anchoring only makes sense for current line)
- The caret column would place annotation before end-of-line text

**Settings addition:**
```pascal
TDXBlameAnnotationPosition = (apEndOfLine, apCaretColumn);
// Property: AnnotationPosition: TDXBlameAnnotationPosition
```

**Risk:** LOW -- single calculation change, no new interfaces, no threading.

### Feature 2: Statusbar Display Mode

**What:** Show blame info in the editor window's status bar, independent of inline annotations.

**Integration point:** `INTAEditWindow.StatusBar` provides direct access to the editor window's TStatusBar. This is the per-editor-window status bar (not the main IDE status bar).

**Architecture:**

```
TDXBlameStatusbar
  implements INTAEditServicesNotifier (partially)
  - EditorViewActivated: update status bar for new view
  - EditorViewModified: update status bar (cursor may have moved)

  uses:
  - INTAEditorServices.TopEditWindow.StatusBar to get TStatusBar
  - BlameEngine.Cache to get blame data
  - Formatter to format annotation text
  - BlameSettings for enabled/format preferences
```

**Status bar panel strategy:** Add a custom TStatusPanel to the existing status bar. The IDE status bar already has panels for line/col, insert/overwrite, etc. We append one panel at the end with blame info.

**Alternative considered:** Using INTACustomEditorViewStatusPanel -- rejected because this is for custom editor views (like Design view), not the Code editor. The Code editor already has its own status bar accessible via INTAEditWindow.StatusBar.

**Update trigger:** The status bar needs updating on every cursor movement. Two options:

1. **INTAEditServicesNotifier.EditorViewModified** -- fires on cursor movement and edits. Best option because it is already part of OTA and fires at the right frequency.
2. **Timer-based polling** -- simpler but wasteful. Reject.

**Independence from inline:** StatusbarEnabled is a separate Boolean, not mutually exclusive with inline. User can have both, either, or neither. This differs from the original feature request which suggested a mode switch -- but independent toggles are more flexible and simpler to implement.

**Cleanup:** Panel must be removed on unload. Store the panel index and remove in finalization.

**Settings additions:**
```pascal
FStatusbarEnabled: Boolean;  // default: False
```

**Risk:** MEDIUM -- accessing IDE status bar at the right lifecycle moment requires care. Panel must survive editor window creation/destruction.

### Feature 3: Context Menu Toggle

**What:** Add "Enable Blame (Ctrl+Alt+B)" item to the editor right-click context menu.

**Integration point:** `TNavigationMenuHandler.OnEditorPopup` in `DX.Blame.Navigation.pas`.

**Implementation:** Add a new TMenuItem with checkmark before the existing "Show revision..." separator:

```
----- (separator)
Enable Blame  Ctrl+Alt+B   [checkmark]
----- (separator)
Show revision 3 days ago
Open in TortoiseHg Annotate
Open in TortoiseHg Log
```

**Code pattern:** Follows identical dynamic-injection pattern already used for "Show revision":
```pascal
// In OnEditorPopup, before existing separator:
GEnableBlameItem := TMenuItem.Create(nil);
GEnableBlameItem.Caption := 'Enable Blame'#9'Ctrl+Alt+B';
GEnableBlameItem.Checked := BlameSettings.Enabled;
GEnableBlameItem.OnClick := Self.OnToggleBlameClick;
TPopupMenu(Sender).Items.Add(GEnableBlameItem);
```

The `#9` (tab character) in the caption is the standard Delphi convention for showing a keyboard shortcut hint right-aligned in a menu item.

**OnToggleBlameClick handler:** Mirrors `TDXBlameMenuHandler.ToggleBlame` from Registration.pas -- toggle `BlameSettings.Enabled`, save, invalidate editors. Also call `SyncEnableBlameCheckmark` via the existing `OnBlameToggled` callback pattern.

**Risk:** LOW -- follows existing pattern exactly, single menu item addition.

### Feature 4: Auto-Scroll Revision to Source Line

**What:** When opening a historical revision via "Show revision...", scroll the temp file to the same line the user was on.

**Integration point:** `NavigateToRevision` in `DX.Blame.Navigation.pas`.

**Current signature:**
```pascal
procedure NavigateToRevision(const AFileName: string;
  const ACommitHash: string; const ARepoRoot: string);
```

**New signature:**
```pascal
procedure NavigateToRevision(const AFileName: string;
  const ACommitHash: string; const ARepoRoot: string;
  ALineNumber: Integer = 0);
```

**Scroll implementation after IOTAActionServices.OpenFile:**
```pascal
// After OpenFile, find the opened view and scroll to line
if ALineNumber > 0 then
begin
  LEditorServices := BorlandIDEServices as IOTAEditorServices;
  LTopView := LEditorServices.TopView;
  if LTopView <> nil then
  begin
    LEditPos.Col := 1;
    LEditPos.Line := ALineNumber;
    LTopView.SetCursorPos(LEditPos);
    LTopView.Center(ALineNumber, 1);
    LTopView.Paint;
  end;
end;
```

Key API: `IOTAEditView40.SetCursorPos(EditPos: TOTAEditPos)` positions the cursor. `IOTAEditView.Center(Row, Col)` scrolls the view so the specified position is centered. Verified in ToolsAPI.pas.

**Caller change:** `TNavigationMenuHandler.OnRevisionClick` must pass the current cursor line:
```pascal
NavigateToRevision(LFileName, LLineInfo.CommitHash, BlameEngine.RepoRoot,
  LLineInfo.FinalLine);
```

**Risk:** LOW -- straightforward OTA API usage. The only subtlety is that OpenFile is synchronous (returns after the file is opened), so TopView should already point to the new file.

### Feature 5: Embedded IDE Options Page

**What:** Replace or supplement the modal Settings dialog with an embedded page in IDE Tools > Options.

**Integration points:**

1. **INTAAddInOptions** (ToolsAPI.pas line 6640) -- interface with 8 methods:
   - `GetArea: string` -- return `''` to appear under "Third Party"
   - `GetCaption: string` -- return `'DX Blame'`
   - `GetFrameClass: TCustomFrameClass` -- return `TFrameDXBlameSettings`
   - `FrameCreated(AFrame: TCustomFrame)` -- call LoadFromSettings on the frame
   - `DialogClosed(Accepted: Boolean)` -- if Accepted, call SaveToSettings
   - `ValidateContents: Boolean` -- validate input, return True if OK
   - `GetHelpContext: Integer` -- return 0 (no help)
   - `IncludeInIDEInsight: Boolean` -- return True (searchable in IDE Insight)

2. **INTAEnvironmentOptionsServices** -- registration/unregistration:
   - `RegisterAddInOptions(const AddInOptions: INTAAddInOptions)`
   - `UnregisterAddInOptions(const AddInOptions: INTAAddInOptions)`

**Unit structure:**

**DX.Blame.Settings.Frame** (new TFrame unit):
- Contains all UI controls currently in TFormDXBlameSettings
- Same GroupBoxes, controls, and layout
- Public methods: `LoadFromSettings`, `SaveToSettings`, `ValidateSettings: Boolean`
- No modal logic, no OK/Cancel buttons (IDE provides those)
- Does NOT use ToolsAPI -- pure VCL frame

**DX.Blame.Settings.Options** (new class unit):
- Implements INTAAddInOptions
- Thin bridge: creates frame, delegates load/save/validate
- References Settings.Frame for GetFrameClass

**Registration changes:**
```pascal
// In Register:
if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, LEnvOptSvc) then
begin
  GAddInOptions := TDXBlameAddInOptions.Create;
  LEnvOptSvc.RegisterAddInOptions(GAddInOptions);
end;

// In finalization (before wizard removal):
if GAddInOptions <> nil then
begin
  if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, LEnvOptSvc) then
    LEnvOptSvc.UnregisterAddInOptions(GAddInOptions);
  GAddInOptions := nil; // prevent double-free -- IDE may release the interface
end;
```

**Tools menu decision:** Keep the Tools > DX Blame menu with "Enable Blame" toggle and "Settings..." item. The "Settings..." item now opens `IOTAEnvironmentOptions.EditOptions('', 'DX Blame')` to navigate directly to the embedded options page. This gives users both access paths. Do NOT remove the Tools menu -- it provides quick toggle access.

**Migration from Settings.Form:** Keep `DX.Blame.Settings.Form` in the package but mark it as legacy. The "Settings..." menu item switches from `TFormDXBlameSettings.ShowSettings` to `EditOptions('', 'DX Blame')`. The modal form remains available as fallback.

**Risk:** MEDIUM -- INTAAddInOptions lifecycle (frame creation/destruction timing) is managed by the IDE. Frame must not hold references that outlive it. Settings.Frame must be stateless between showings.

## Patterns to Follow

### Pattern 1: Settings Property + INI Persistence

**What:** Every new setting follows the established pattern in TDXBlameSettings.

**When:** Adding any configurable behavior.

**Example:**
```pascal
// In TDXBlameSettings:
private
  FAnnotationPosition: TDXBlameAnnotationPosition;
public
  property AnnotationPosition: TDXBlameAnnotationPosition
    read FAnnotationPosition write FAnnotationPosition;

// In Load:
LPosStr := LIni.ReadString('Display', 'AnnotationPosition', 'EndOfLine');
if SameText(LPosStr, 'CaretColumn') then
  FAnnotationPosition := apCaretColumn
else
  FAnnotationPosition := apEndOfLine;

// In Save:
case FAnnotationPosition of
  apEndOfLine: LIni.WriteString('Display', 'AnnotationPosition', 'EndOfLine');
  apCaretColumn: LIni.WriteString('Display', 'AnnotationPosition', 'CaretColumn');
end;
```

### Pattern 2: Dynamic Context Menu Injection

**What:** Items injected in OnEditorPopup, cleaned up in RemoveOurItems.

**When:** Adding new context menu items.

**Example:** The existing "Show revision..." and TortoiseHg items follow this exactly. The new "Enable Blame" item follows the same pattern with an additional `Checked` property.

### Pattern 3: INTAAddInOptions Bridge

**What:** Thin adapter class implements INTAAddInOptions, delegates to a TFrame.

**When:** Embedding settings in IDE Options.

**Example:**
```pascal
TDXBlameAddInOptions = class(TInterfacedObject, INTAAddInOptions)
private
  FFrame: TFrameDXBlameSettings;
public
  function GetArea: string;           // returns ''
  function GetCaption: string;        // returns 'DX Blame'
  function GetFrameClass: TCustomFrameClass;  // returns TFrameDXBlameSettings
  procedure FrameCreated(AFrame: TCustomFrame);
  procedure DialogClosed(Accepted: Boolean);
  function ValidateContents: Boolean;
  function GetHelpContext: Integer;    // returns 0
  function IncludeInIDEInsight: Boolean; // returns True
end;
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Mutually Exclusive Display Modes

**What:** Making inline and statusbar mutually exclusive (radio button choice).

**Why bad:** Limits flexibility. Users may want both (inline for details, statusbar for quick reference). Increases settings complexity with mode enums.

**Instead:** Two independent Booleans: `Enabled` (existing, controls inline) and `StatusbarEnabled` (new, controls statusbar). They are orthogonal.

### Anti-Pattern 2: Frame Holding Persistent State

**What:** Storing runtime state in TFrameDXBlameSettings that persists across IDE Options dialog openings.

**Why bad:** The IDE may destroy and recreate the frame at any time. Frame lifetime is not under our control.

**Instead:** Frame reads from TDXBlameSettings singleton on FrameCreated, writes back on DialogClosed(True). Frame is a pure view -- no persistent state.

### Anti-Pattern 3: Polling for Status Bar Updates

**What:** Using a TTimer to periodically check cursor position and update the status bar.

**Why bad:** Wasteful CPU cycles, introduces update latency, adds timer lifecycle management.

**Instead:** Use INTAEditServicesNotifier.EditorViewModified which fires on every cursor movement and edit. Existing IDE.Notifier already uses this pattern.

### Anti-Pattern 4: Removing the Tools Menu

**What:** Completely replacing Tools > DX Blame with the IDE Options page.

**Why bad:** IDE Options requires multiple clicks (Tools > Options > Third Party > DX Blame). The toggle needs to be fast (one click or one keystroke). Power users expect menu-bar access.

**Instead:** Keep Tools menu for quick toggle. Change "Settings..." to open the IDE Options dialog directly at the DX Blame page.

## Data Flow Changes

### Annotation Position Data Flow

```
TDXBlameSettings.AnnotationPosition
  --> TDXBlameRenderer.PaintLine
    --> LAnnotationX calculation branches on setting
    --> Canvas.TextOut at computed X
```

No new data structures. Pure branching logic in one method.

### Statusbar Data Flow

```
EditorViewModified/EditorViewActivated (IDE event)
  --> TDXBlameStatusbar.UpdatePanel
    --> Read caret line from IOTAEditView.CursorPos.Line
    --> Read blame data from BlameEngine.Cache.TryGet
    --> Format via FormatBlameAnnotation
    --> Write to INTAEditWindow.StatusBar.Panels[N].Text
```

Uses existing data pipeline (Cache + Formatter). No new data formats.

### Auto-Scroll Data Flow

```
OnRevisionClick (context menu)
  --> TryGetCurrentLineInfo (gets FinalLine)
  --> NavigateToRevision(FileName, Hash, RepoRoot, LineNumber)
    --> IOTAActionServices.OpenFile (opens temp file)
    --> IOTAEditView.SetCursorPos (positions cursor)
    --> IOTAEditView.Center (scrolls view)
```

Single integer parameter threaded through existing call chain.

## Build Order (Dependency-Driven)

Dependencies flow: Settings --> Frame/Statusbar --> Options --> Registration.

| Phase | Units | Rationale |
|-------|-------|-----------|
| **1** | `DX.Blame.Settings` (modify) | All features depend on new settings properties. Zero risk, pure data. |
| **2** | `DX.Blame.Renderer` (modify) | Feature 1 (annotation positioning). Depends on Phase 1 settings. Self-contained in one method. |
| **3** | `DX.Blame.Navigation` (modify) | Features 3+4 (context menu toggle + auto-scroll). Independent of Phase 2. Depends on Phase 1 settings. |
| **4** | `DX.Blame.Settings.Frame` (new) | Feature 5 prerequisite. Extract UI from Settings.Form into TFrame. No OTA dependency. |
| **5** | `DX.Blame.Settings.Options` (new) | Feature 5 INTAAddInOptions adapter. Depends on Phase 4 frame. |
| **6** | `DX.Blame.Statusbar` (new) | Feature 2. Independent of Phases 4-5. Depends on Phase 1 settings. Separate because it introduces a new OTA notifier. |
| **7** | `DX.Blame.Registration` (modify) + `DX.Blame.dpk` (modify) | Wire everything: register Options page, register Statusbar notifier, update menu "Settings..." action, add new units to dpk. |

Phases 2, 3, and 6 are independent of each other and could be parallelized. Phase 4 must precede Phase 5. Phase 7 is the integration phase that ties everything together.

## Scalability Considerations

Not applicable for this milestone -- all changes are local to the IDE process with negligible performance impact. The statusbar update fires on cursor movement but performs only a dictionary lookup and string format (sub-millisecond).

## Sources

- ToolsAPI.pas (Delphi 13, Studio 37.0) -- INTAAddInOptions interface (line 6640), INTAEditWindow.StatusBar (line 2235), INTAEnvironmentOptionsServices (line 6760), INTACustomEditorViewStatusPanel (line 8020, evaluated and rejected)
- [IOTAEditView40.SetCursorPos](https://docwiki.embarcadero.com/Libraries/Athens/en/API:ToolsAPI.IOTAEditView40.SetCursorPos) -- cursor positioning API
- [Embarcadero OTAPI-Docs](https://github.com/Embarcadero/OTAPI-Docs) -- OTA documentation
- [GExperts OTA FAQ](https://www.gexperts.org/open-tools-api-faq/) -- practical OTA patterns
- Existing DX.Blame codebase (28 units, v1.1) -- architecture patterns and conventions
