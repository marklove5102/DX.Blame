object DXBlamePopup: TDXBlamePopup
  Left = 0
  Top = 0
  BorderStyle = bsNone
  ClientHeight = 200
  ClientWidth = 400
  Color = clWindow
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  Position = poDesigned
  Scaled = True
  PixelsPerInch = 96
  TextHeight = 15
  object HashLabel: TLabel
    Left = 10
    Top = 10
    Width = 50
    Height = 15
    Cursor = crHandPoint
    Caption = 'abc1234'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clBlue
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsUnderline, fsBold]
    ParentFont = False
    OnClick = DoHashClick
  end
  object AuthorLabel: TLabel
    Left = 10
    Top = 31
    Width = 380
    Height = 15
    AutoSize = True
    Caption = 'Author'
  end
  object DateLabel: TLabel
    Left = 10
    Top = 50
    Width = 380
    Height = 15
    AutoSize = True
    Caption = 'Date'
  end
  object LoadingLabel: TLabel
    Left = 10
    Top = 73
    Width = 56
    Height = 15
    Caption = 'Loading...'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsItalic]
    ParentFont = False
    Visible = False
  end
  object MessageMemo: TMemo
    Left = 10
    Top = 73
    Width = 380
    Height = 64
    BorderStyle = bsNone
    ReadOnly = True
    ScrollBars = ssVertical
    TabStop = False
    WordWrap = True
  end
  object ShowDiffButton: TButton
    Left = 300
    Top = 145
    Width = 90
    Height = 25
    Caption = 'Show Diff'
    TabOrder = 1
    OnClick = DoShowDiffClick
  end
  object CopiedTimer: TTimer
    Enabled = False
    Interval = 1500
    OnTimer = DoCopiedTimerTick
    Left = 200
    Top = 145
  end
end
