/// <summary>
/// DX.Blame.Hg.Process
/// Thin Mercurial-specific subclass of the VCS process wrapper.
/// </summary>
///
/// <remarks>
/// Provides THgProcess as a convenience subclass of TVCSProcess.
/// All CreateProcess and pipe capture logic lives in the base class.
/// THgProcess exists to preserve the Mercurial-specific constructor
/// signature and property name (HgPath) used by provider code.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Blame.Hg.Process;

interface

uses
  Winapi.Windows,
  DX.Blame.VCS.Process;

type
  /// <summary>
  /// Mercurial-specific process wrapper. Inherits all execution logic from
  /// TVCSProcess and adds an HgPath convenience property.
  /// </summary>
  THgProcess = class(TVCSProcess)
  public
    /// <summary>Creates a process wrapper for the given hg executable and working directory.</summary>
    constructor Create(const AHgPath, AWorkDir: string);

    /// <summary>Full path to the hg executable.</summary>
    property HgPath: string read FExePath;
  end;

implementation

{ THgProcess }

constructor THgProcess.Create(const AHgPath, AWorkDir: string);
begin
  inherited Create(AHgPath, AWorkDir);
end;

end.
