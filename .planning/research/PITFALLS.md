# Domain Pitfalls

**Domain:** Adding UX Polish & IDE Integration to Existing Delphi OTA Plugin (v1.2)
**Researched:** 2026-03-26

This document covers pitfalls specific to the v1.2 milestone features: INTAAddInOptions TFrame-based IDE Options page, statusbar blame display, context menu toggle, auto-scroll revision navigation, and annotation X positioning. The v1.0 pitfalls (OTA notifiers, CreateProcess, PaintLine performance) and v1.1 pitfalls (VCS abstraction, Mercurial parsing) remain valid and are not repeated.

## Critical Pitfalls

Mistakes that cause access violations, IDE instability, or require significant rework.

### Pitfall 1: INTAAddInOptions Frame Lifecycle Misunderstanding

**What goes wrong:** Developer stores a reference to the TFrame instance created by the IDE and uses it after the Options dialog closes. The IDE creates and destroys the frame each time the user opens Tools > Options. The frame reference becomes a dangling pointer.
**Why it happens:** The `FrameCreated(AFrame: TCustomFrame)` callback receives the frame instance, and developers naturally store it for later use. But the IDE owns the frame and destroys it when the dialog closes. The `DialogClosed(Accepted: Boolean)` callback fires BEFORE the frame is destroyed, so reading frame state in `DialogClosed` is safe, but keeping the reference afterward is not.
**Consequences:** Access violation when trying to read settings from a destroyed frame, or when the Options dialog is opened a second time and the old reference conflicts with the new frame.
**Prevention:**
1. In `FrameCreated`, store the reference in a field (e.g., `FSettingsFrame`) AND populate the frame controls from settings.
2. In `DialogClosed(True)`, read the frame control values back to settings, then set `FSettingsFrame := nil`.
3. NEVER access `FSettingsFrame` outside these two callbacks.
4. The INTAAddInOptions implementor itself (the class implementing the interface) must be kept alive for the entire plugin lifetime -- register it during `Register` and unregister in `finalization`.
**Detection:** Open Tools > Options, click OK. Open again. If it crashes, the frame reference was not cleared.

### Pitfall 2: INTAAddInOptions Registration/Unregistration Order

**What goes wrong:** Developer registers the AddInOptions via `INTAEnvironmentOptionsServices.RegisterAddInOptions` but forgets to call `UnregisterAddInOptions` during finalization, or calls it at the wrong point in the cleanup sequence. The IDE retains a reference to the INTAAddInOptions implementor. On BPL unload, the IDE calls into freed memory when the user next opens Tools > Options.
**Why it happens:** The existing finalization in `DX.Blame.Registration` has a carefully ordered 8-step cleanup sequence (DetachContextMenu, UnregisterKeyBinding, CleanupPopup, UnregisterRenderer, UnregisterIDENotifiers, RemoveToolsMenu, RemoveWizard, RemoveAboutBox). Adding INTAAddInOptions registration means inserting unregistration at the right position. Unlike wizard registration (which returns an integer index for removal), AddInOptions registration uses the interface reference itself for unregistration.
**Consequences:** AV in the IDE when opening Tools > Options after unloading the plugin. In severe cases, the IDE crashes on next startup if it caches the Options tree.
**Prevention:**
- Store the INTAAddInOptions interface reference in a unit-level variable (not just a local).
- Register in `Register` procedure, after wizard registration but before `CreateToolsMenu` (since the Tools menu "Settings..." item may need to reference the Options page).
- Unregister in `finalization`, BEFORE wizard removal (step 7 in current sequence). The Options page must be removed while `BorlandIDEServices` is still valid.
- Insert as step 6.5 in the existing cleanup: after RemoveToolsMenu (step 6) but before RemoveWizard (step 7).
- The current finalization sequence should become:
  1. DetachContextMenu
  2. UnregisterKeyBinding
  3. CleanupPopup
  4. UnregisterRenderer
  5. UnregisterIDENotifiers
  6. RemoveToolsMenu
  7. **UnregisterAddInOptions** (NEW)
  8. RemoveWizard
  9. RemoveAboutBox
**Detection:** Install package, open Tools > Options (verify page shows), uninstall package, open Tools > Options again. No crash = correct cleanup.

### Pitfall 3: Statusbar Panel Not Updating on Cursor Movement

**What goes wrong:** Developer adds a statusbar panel via `INTAEditWindow.StatusBar` and writes blame text to it during initialization or on file open. But the text never updates when the user moves the cursor to a different line.
**Why it happens:** Unlike the renderer's `PaintLine` (which fires on every paint cycle), there is no automatic callback for statusbar updates on cursor movement. The existing `EditorSetCaretPos` in `TDXBlameRenderer` fires on cursor movement but currently only stores `FCurrentEditor` and calls `InvalidateAllEditors` -- it does not update statusbar text.
**Consequences:** Statusbar shows stale blame info for the wrong line. User sees "John, 3 days ago" permanently regardless of which line they are on.
**Prevention:** Two approaches:
1. **Piggyback on EditorSetCaretPos:** When the renderer's `EditorSetCaretPos` fires, also update the statusbar panel text. This requires extracting statusbar update logic into a shared unit (e.g., `DX.Blame.Statusbar`) callable from the renderer without circular dependencies.
2. **Use INTAEditServicesNotifier.EditorViewActivated:** Register an `INTAEditServicesNotifier` to detect view switches. Combined with `EditorSetCaretPos` for cursor movement within a view, this covers all cases.

In both approaches, the update must: get the current `IOTAEditView`, read `CursorPos.Line`, look up blame data from cache, format the statusbar text, and write it to the panel. This must be fast (no blocking calls). The existing `BlameEngine.Cache.TryGet` is already O(1) dictionary lookup, so this is safe.
**Detection:** Move cursor between lines. Statusbar text should change on each line change.

### Pitfall 4: Multiple Edit Windows Break Context Menu and Statusbar

**What goes wrong:** The current `AttachContextMenu` hooks `EditorLocalMenu` from `TopEditWindow.Form`. When the user opens a second edit window (View > New Edit Window), that window has its OWN `EditorLocalMenu` and its OWN statusbar. The plugin's context menu items and statusbar panel only appear in the first window.
**Why it happens:** `FindEditorPopupMenu` in `DX.Blame.Navigation` calls `LNTAServices.TopEditWindow` which returns only ONE edit window. The IDE can have multiple. Each edit window is an independent form with independent popup menu and statusbar instances.
**Consequences:** Context menu toggle item missing in secondary edit windows. Statusbar blame info missing in secondary windows. User reports "it works in one window but not the other."
**Prevention:**
- For **context menu**: Use `INTAEditServicesNotifier.WindowNotification` with `Operation = opInsert` to detect new edit windows as they are created. Hook each window's `EditorLocalMenu` independently. Maintain a list of hooked popup menus (replace the current `GHookedPopup: TPopupMenu` singleton with `GHookedPopups: TList<TPopupMenu>`). On `opRemove`, unhook and remove from list.
- For **statusbar**: Similarly, access each edit window's statusbar. Update the statusbar of the ACTIVE edit window (track via `WindowActivated`).
- **Important subtlety in current code:** `DetachContextMenu` only restores `GOriginalOnPopup` when `Assigned(GOriginalOnPopup)` is True. If the original `OnPopup` was nil (which it often is for `EditorLocalMenu`), detaching leaves the popup with the plugin's handler assigned. Fix: always set `GHookedPopup.OnPopup := GOriginalOnPopup` regardless of whether `GOriginalOnPopup` is assigned.
- Consider whether the v1.2 scope requires multi-window support or if documenting it as a known limitation is acceptable for now.
**Detection:** Open a second edit window. Check if the context menu item and statusbar panel appear in both windows.

## Moderate Pitfalls

### Pitfall 5: Auto-Scroll After OpenFile Timing Race

**What goes wrong:** After calling `IOTAActionServices.OpenFile(LTempFile)` in `NavigateToRevision`, the developer immediately tries to set the cursor position via `IOTAEditView.SetCursorPos` and `SetTopPos`. The call fails silently or positions to line 1 because the file is not yet fully loaded and the edit view is not ready.
**Why it happens:** `OpenFile` may be asynchronous in some IDE versions. The module may not be immediately available via `IOTAModuleServices.FindModule`. Even when it is, the edit view might not have finished layout/rendering, so `SetCursorPos` has no effect.
**Consequences:** The historical revision file opens but the user sees line 1 instead of the line they right-clicked on. The entire purpose of auto-scroll is defeated.
**Prevention:**
1. After `OpenFile`, use `IOTAModuleServices.FindModule(LTempFile)` to get the module.
2. Iterate the module's `IOTAEditor` interfaces to find the `IOTASourceEditor`.
3. Call `LSourceEditor.Show` to ensure the editor view is active.
4. Get the top edit view and call `SetCursorPos` with the target line.
5. Use `IOTAEditView140.Center(Row, Col)` to center the target line in the visible area (better UX than just setting cursor).
6. If `FindModule` returns nil, use a short `TTimer` (50-100ms one-shot) to retry. Follow the existing engine pattern: create a one-shot TTimer, free it in OnTimer after use. Do NOT use a busy-wait loop.
**Codebase integration note:** The current `NavigateToRevision` in `DX.Blame.Navigation` already calls `LActionServices.OpenFile(LTempFile)` at line 162. The auto-scroll code should be added immediately after this call, with the `FindModule` check and timer fallback. The target line number must be passed from the caller (the commit popup or context menu click handler, which knows the clicked line from `TryGetCurrentLineInfo`).
**Detection:** Right-click line 150 in a 500-line file, choose "Show revision..." -- the temp file should open scrolled to around line 150.

### Pitfall 6: Annotation X Positioning Flicker When Caret Changes

**What goes wrong:** Caret-anchored annotation X positioning recalculates the annotation X coordinate on every cursor movement. When the user types or navigates, the annotation jumps between positions on every keystroke, causing visible flicker.
**Why it happens:** The current `PaintLine` in `TDXBlameRenderer` computes `LAnnotationX := Context.LineState.VisibleTextRect.Right + (Context.CellSize.cx * 3)`. This is line-end-anchored. Changing this to caret-anchored means the X position depends on the caret column, which changes on every keystroke. Each paint cycle triggered by `InvalidateAllEditors` (called from `EditorSetCaretPos`) recalculates X.
**Consequences:** Distracting visual flicker. Annotation text appears to "dance" left and right as the user types.
**Prevention:**
- The "caret-anchored" positioning should NOT follow the caret column. Instead, it should anchor annotations at a fixed X offset from the caret LINE's visible text end (as currently done), but with a configurable minimum X column so annotations align vertically across lines. The name is misleading -- "caret-anchored" means "follows the active line," not "follows the caret column."
- When the buffer is modified (`IsModified = True`), blame annotations are already hidden (existing code checks this at Renderer line 279), so flicker during typing is not an issue. The concern is navigating within unmodified files where annotations on different lines have different X positions due to varying line lengths.
- Configurable modes: (1) Line-end-anchored (current behavior), (2) Fixed-column-anchored (all annotations at a constant X offset, e.g., column 80 * CellWidth).
**Detection:** In a file with varying line lengths, rapidly press Up/Down arrow keys. The annotation should NOT jump horizontally between lines of different lengths.

### Pitfall 7: Context Menu Toggle Item Caption Stale After Hotkey Toggle

**What goes wrong:** The context menu "Enable DX Blame (Ctrl+Alt+B)" item shows the wrong check state because the user toggled blame via the keyboard shortcut (Ctrl+Alt+B) between right-clicks. The menu item was injected in `OnEditorPopup` with the state at popup time, but the caption or check mark reflects the previous state.
**Why it happens:** The current `OnEditorPopup` handler in `DX.Blame.Navigation` creates menu items fresh each time via `RemoveOurItems` + re-creation, reading the current `BlameSettings.Enabled` state. This pattern handles this correctly IF items are re-created on each popup. The pitfall is if the developer optimizes by caching the menu item and only creating it once -- then the check state becomes stale.
**Consequences:** User sees "Enable DX Blame" as checked when it is actually disabled, or vice versa.
**Prevention:** The existing pattern of removing and re-creating items in `OnEditorPopup` (via `RemoveOurItems` + fresh creation) already handles this correctly. Keep this pattern for the new toggle item. Do NOT optimize by caching the menu item across popup invocations.
**Detection:** Toggle blame via Ctrl+Alt+B, then right-click in editor. The context menu toggle state should match the actual state.

### Pitfall 8: INTAAddInOptions GetArea/GetCaption Nested Path Gotcha

**What goes wrong:** Developer returns a non-empty string from `GetArea` (e.g., "DX Blame") and a simple string from `GetCaption` (e.g., "Settings"). The page appears at an unexpected location in the Options tree, possibly conflicting with another plugin's area name.
**Why it happens:** The ToolsAPI source comments explicitly state: "It is strongly suggested that you return an empty string from [GetArea]." Returning empty places the page under "Third Party", which is the conventional location for third-party plugin settings. Using a custom area may not display correctly in all IDE versions or may get lost in the tree.
**Consequences:** Users cannot find the settings page because it is not where they expect it (under "Third Party"). Or the page appears at an unexpected tree level.
**Prevention:**
- Return `''` (empty string) from `GetArea`. This places the page under "Third Party."
- Return `'DX Blame'` from `GetCaption` for a single-level entry, or `'DX Blame.Settings'` if sub-pages are needed later.
- Return `True` from `IncludeInIDEInsight` so the page is findable via IDE Insight (Ctrl+.).
**Detection:** Open Tools > Options, verify the page appears under "Third Party" > "DX Blame".

### Pitfall 9: Settings Migration -- Standalone Dialog vs. Options Page Dual State

**What goes wrong:** After adding the INTAAddInOptions page, the developer removes the standalone `TFormDXBlameSettings` dialog immediately. Users who had the old version lose their workflow (Tools > DX Blame > Settings), and the transition is jarring.
**Why it happens:** The milestone says "remove Tools menu," but removing it immediately creates a breaking change. Users upgrading from v1.1 to v1.2 find their muscle memory broken.
**Consequences:** User confusion. Bug reports about "missing settings." Potential data loss if settings migration between the two forms is incomplete.
**Prevention:**
- Phase the transition: first ADD the IDE Options page (keep the Tools > DX Blame menu working). Verify the Options page works correctly with all settings.
- The Tools menu "Settings..." item should redirect to open the IDE Options dialog focused on the DX Blame page. This way the menu item still works but opens the new location.
- Remove the standalone dialog form AFTER confirming the Options page handles all settings correctly.
- Settings persistence (INI file) stays the same -- both the frame and the old dialog read/write the same `TDXBlameSettings` singleton. The existing `LoadFromSettings`/`SaveToSettings` pattern from `TFormDXBlameSettings` can be reused directly in the frame's `FrameCreated`/`DialogClosed` callbacks.
- **Critical detail:** The existing `SaveToSettings` in `DX.Blame.Settings.Form` also triggers `InvalidateAllEditors` and `BlameEngine.OnProjectSwitch` when VCS preference changes. The new Options page `DialogClosed` must replicate this behavior exactly, not just save settings.
**Detection:** Upgrade from v1.1 to v1.2. Verify all settings are preserved and accessible from both entry points during transition.

### Pitfall 10: INTAEditWindow.StatusBar Panel Index Conflict

**What goes wrong:** Developer adds a status panel to the editor's TStatusBar by calling `StatusBar.Panels.Add`. The panel index conflicts with the IDE's own panels (line/col, insert/overwrite, modified indicator). Adding panels at runtime shifts existing panel indices, potentially breaking IDE internal code that references panels by index.
**Why it happens:** The IDE's statusbar already has panels with specific purposes mapped to specific indices. Adding a panel via `Panels.Add` appends at the end, which is safest. But if the developer tries to insert at a specific position, or if the IDE version changes the number of built-in panels, the layout breaks.
**Consequences:** IDE's own statusbar information (line number, modified state) shifts or disappears. In the worst case, the IDE crashes when updating its own panels because the indices changed.
**Prevention:**
- ALWAYS add panels at the end via `StatusBar.Panels.Add`, never `Insert`.
- Store the added panel's `Index` value for later updates and cleanup.
- On cleanup (finalization), remove only your panels. Use the stored index to identify them. Remove in reverse order.
- Check the panel count before and after adding to verify no conflicts.
- Use a fixed width for the DX Blame panel (e.g., 250 pixels) -- do not set `AutoSize := True` as the blame text length varies and would cause layout jitter.
- Set the panel's `Style := psText` and update `Text` directly -- do not use owner-draw (`psOwnerDraw`) unless absolutely necessary, as it introduces additional threading concerns.
**Detection:** After adding the panel, verify the IDE's built-in statusbar info (line/col, insert mode) still displays correctly.

## Minor Pitfalls

### Pitfall 11: ValidateContents Return Value Ignored

**What goes wrong:** The INTAAddInOptions `ValidateContents` method returns `False` (indicating invalid input), but the developer does not display an error message. The IDE prevents the dialog from closing, but the user has no idea why.
**Prevention:** Always show a `MessageDlg` or focus the invalid control before returning `False` from `ValidateContents`. For DX Blame settings (which are simple checkboxes and combos), `ValidateContents` should almost always return `True`. The only validation needed is for numeric fields (MaxLength > 0).

### Pitfall 12: GetHelpContext Returns Non-Zero Without Help File

**What goes wrong:** `GetHelpContext` returns a non-zero value but no help file is registered. Pressing F1 on the Options page does nothing or shows a "topic not found" error.
**Prevention:** Return `0` from `GetHelpContext` unless you have actually registered a help file with the IDE. Zero means "no context help."

### Pitfall 13: IOTAEditView.CursorPos Does Not Update StatusBar

**What goes wrong:** Setting `IOTAEditView.CursorPos` programmatically (for auto-scroll) moves the cursor in the edit buffer but does NOT update the IDE's own statusbar cursor position display.
**Why it happens:** This is a known OTA quirk: "Setting IOTAEditView.CursorPos doesn't update the edit window's cursor position in the status bar."
**Prevention:** After setting `CursorPos`, call `IOTAEditView.Paint` to force a full view update. Alternatively, use `IOTAEditView140.Center(Row, Col)` which both positions the cursor and triggers a proper view update including the statusbar.

### Pitfall 14: Annotation X Position Exceeds Editor Client Width

**What goes wrong:** The caret-anchored annotation X position places the annotation beyond the right edge of the visible editor area when the caret is at a high column number. The annotation is painted but never visible without horizontal scrolling.
**Prevention:** Clamp the annotation X to `min(CalculatedX, EditorClientWidth - AnnotationTextWidth - Padding)`. If the annotation would extend beyond the visible area, either truncate the text or position it at the maximum visible X. The `Editor.ClientWidth` property gives the visible width. The current renderer already has access to the `Editor: TWinControl` parameter in paint events.

### Pitfall 15: TFrame DPI Scaling in IDE Options Dialog

**What goes wrong:** The TFrame for the IDE Options page has controls designed at 96 DPI. On high-DPI displays, the controls appear too small or overlap because the IDE Options dialog may or may not apply DPI scaling to the embedded frame.
**Why it happens:** The IDE handles DPI scaling for its own dialogs, but embedded third-party frames may not receive the `ChangeScale` call or `ParentFont` propagation depending on how they are parented.
**Consequences:** Controls overlap, text is clipped, or the frame is too small on 4K displays.
**Prevention:**
- Design the frame with `AlignWithMargins` and anchoring rather than absolute pixel positions.
- Use `TFlowPanel` or `TGridPanel` where appropriate for responsive layout.
- Test at 100%, 150%, and 200% display scaling.
- Set `ParentFont := True` on the frame so it inherits the IDE's font (which is DPI-aware).
- The existing `TFormDXBlameSettings` uses absolute positioning (GroupBox coordinates). The new TFrame should NOT copy these coordinates -- redesign with anchoring.

### Pitfall 16: Statusbar Panel Cleanup Race With Edit Window Destruction

**What goes wrong:** During finalization, the plugin tries to remove its statusbar panel from an edit window that has already been destroyed by the IDE. The panel reference is dangling, and `StatusBar.Panels.Delete` causes an AV.
**Why it happens:** The IDE may close edit windows before the plugin's finalization runs, especially during IDE shutdown. If the plugin stores a reference to the statusbar panel but the edit window form is already freed, accessing the panel crashes.
**Prevention:**
- Track statusbar panel additions per edit window form. Use the form's `FreeNotification` mechanism (call `LForm.FreeNotification(GStatusBarTracker)`) to receive notification when the form is destroyed, so the plugin can remove the panel reference without trying to access a freed object.
- Alternatively, wrap panel removal in a try/except during finalization -- but this is a band-aid, not a fix.
- During normal cleanup (not IDE shutdown), remove panels in reverse registration order before the edit window is destroyed.

## Delphi Version-Specific Warnings

### Delphi 11 vs 12 vs 13 Differences

| Feature Area | Delphi 11 | Delphi 12 | Delphi 13 | Impact |
|---|---|---|---|---|
| INTAAddInOptions | Stable, unchanged since Delphi 2007 | Same interface | Same interface | LOW risk -- interface unchanged |
| INTAEditWindow.StatusBar | TStatusBar, works | Same | Same | LOW risk |
| INTACodeEditorEvents370 | Not available | Available | Available | Use `{$IF CompilerVersion >= 36.0}` for 370-specific features |
| IOTAEditView.Center | Available (IOTAEditView140) | Available | Available | LOW risk |
| EditorLocalMenu component name | `'EditorLocalMenu'` | Same | Same | LOW risk -- unchanged across versions |
| IDE Options dialog layout | Classic tree | Modernized in 12.2+ | Further refined | TFrame layout may need testing per version |
| DPI handling in Options frames | Manual | Improved | Further improved | Test frame layout at all DPI levels per version |
| Resource compilation (BRCC32 vs RLINK32) | RLINK32 works | Either works | Must use BRCC32 (16-bit RLINK32 error) | Already handled in v1.0 |

**Key observation:** The INTAAddInOptions interface has not changed since its introduction. This is LOW risk for cross-version compatibility.

**The main cross-version risk is DPI scaling behavior in the Options dialog frame**, which differs subtly between IDE versions. Test the TFrame layout on each supported Delphi version at high DPI.

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|---|---|---|
| INTAAddInOptions page | Pitfall 1 (frame lifecycle), Pitfall 2 (registration order), Pitfall 8 (GetArea) | Store reference, nil in DialogClosed, return empty GetArea, unregister before wizard |
| Settings migration | Pitfall 9 (dual state) | Keep Tools menu during transition, redirect to IDE Options |
| Statusbar display | Pitfall 3 (no auto-update), Pitfall 4 (multiple windows), Pitfall 10 (panel index), Pitfall 16 (cleanup race) | Update on caret change, add panel at end, handle multi-window, use FreeNotification |
| Context menu toggle | Pitfall 4 (multiple windows), Pitfall 7 (stale state) | Re-create items each popup, hook all edit windows |
| Auto-scroll revision | Pitfall 5 (timing race), Pitfall 13 (CursorPos statusbar) | FindModule + retry timer, use Center() |
| Annotation X positioning | Pitfall 6 (flicker), Pitfall 14 (overflow) | Fixed-column mode, clamp to client width |
| Cross-version | Pitfall 15 (DPI scaling) | Anchor-based layout, test at 150%+ DPI on all 3 IDE versions |

## Sources

- [GExperts OTA FAQ](https://www.gexperts.org/open-tools-api-faq/) -- EditorLocalMenu component name, CursorPos statusbar quirk, context menu action limitation, interface release rules. HIGH confidence.
- [Embarcadero OTAPI-Docs](https://github.com/Embarcadero/OTAPI-Docs/blob/main/The%20Delphi%20IDE%20Open%20Tools%20API%20-%20Version%201.2.md) -- General OTA documentation, INTAAddInOptions overview. MEDIUM confidence.
- [DGH2112 OTA-Template](https://github.com/DGH2112/OTA-Template) -- Reference OTA plugin implementation with options page patterns. MEDIUM confidence.
- [Extending the Delphi IDE (Embarcadero)](https://docwiki.embarcadero.com/RADStudio/Athens/en/Extending_the_IDE_Using_the_Tools_API) -- Official IDE extension documentation. MEDIUM confidence.
- Existing DX.Blame codebase analysis -- Registration.pas (finalization order lines 304-333), Renderer.pas (PaintLine X calculation lines 310-311, EditorSetCaretPos lines 169-177), Navigation.pas (AttachContextMenu lines 373-390, DetachContextMenu lines 392-403, NavigateToRevision lines 120-163), Settings.pas (INI persistence), Settings.Form.pas (SaveToSettings side effects lines 142-180). HIGH confidence.
