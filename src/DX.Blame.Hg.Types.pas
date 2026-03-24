/// <summary>
/// DX.Blame.Hg.Types
/// Mercurial-specific sentinel constants for uncommitted line detection.
/// </summary>
///
/// <remarks>
/// Contains only Mercurial-specific constants that do not belong in the
/// VCS-neutral type layer. Mirrors DX.Blame.Git.Types for the Mercurial
/// provider. The uncommitted hash uses the full 40-character node format
/// as returned by hg annotate -T "{node}".
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DX.Blame.Hg.Types;

interface

uses
  DX.Blame.VCS.Types;

const
  /// <summary>Full 40-char node hash sentinel for uncommitted working directory changes.</summary>
  cHgUncommittedHash = 'ffffffffffffffffffffffffffffffffffffffff';

  /// <summary>Display author name for uncommitted lines.</summary>
  cHgNotCommittedAuthor = 'Not Committed';

implementation

end.
