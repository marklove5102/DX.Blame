object FormDXBlameDiff: TFormDXBlameDiff
  Left = 0
  Top = 0
  Caption = 'Commit Diff'
  ClientHeight = 600
  ClientWidth = 800
  Color = clWindow
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  Position = poScreenCenter
  Scaled = True
  PixelsPerInch = 96
  TextHeight = 15
  object PanelHeader: TPanel
    Left = 0
    Top = 0
    Width = 800
    Height = 120
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object LabelHash: TLabel
      Left = 10
      Top = 8
      Width = 50
      Height = 15
      Caption = 'abc1234'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clNavy
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object LabelAuthor: TLabel
      Left = 10
      Top = 28
      Width = 40
      Height = 15
      Caption = 'Author'
    end
    object LabelDate: TLabel
      Left = 10
      Top = 46
      Width = 24
      Height = 15
      Caption = 'Date'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGray
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object MemoMessage: TMemo
      Left = 10
      Top = 66
      Width = 780
      Height = 48
      Anchors = [akLeft, akTop, akRight]
      BorderStyle = bsNone
      ReadOnly = True
      ScrollBars = ssVertical
      TabOrder = 0
      TabStop = False
      WordWrap = True
    end
  end
  object PanelToolbar: TPanel
    Left = 0
    Top = 120
    Width = 800
    Height = 32
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 1
    object LabelLoading: TLabel
      Left = 200
      Top = 7
      Width = 56
      Height = 15
      Caption = 'Loading...'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGray
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsItalic]
      ParentFont = False
      Visible = False
    end
    object ButtonToggleScope: TButton
      Left = 10
      Top = 3
      Width = 180
      Height = 25
      Caption = 'Show Full Commit Diff'
      TabOrder = 0
      OnClick = DoToggleScopeClick
    end
  end
  object RichEditDiff: TRichEdit
    Left = 0
    Top = 152
    Width = 800
    Height = 448
    Align = alClient
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -13
    Font.Name = 'Consolas'
    Font.Style = []
    HideSelection = False
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssBoth
    TabOrder = 2
    WordWrap = False
  end
end
