program VideoCounter;

{$APPTYPE CONSOLE}

uses
  Windows,
  Types,
  Uavi,
  SysUtils,
  Graphics;

var
  Images: array[0..9] of TBitmap;
  Alpha: array[0..255] of TBitmap;
  Image, Papper: TBitmap;

const
  font_dir = './font/';

procedure CollectImages();
var
  Index: Integer;
  Bitmap: TBitmap;
begin
  for Index := 0 to 9 do
  begin
    Bitmap := TBitmap.Create();
    Bitmap.LoadFromFile(font_dir + '_' + IntToStr(Index) + '.bmp');
    Bitmap.PixelFormat := pf32bit;
    Images[Index] := Bitmap;
  end;
end;

procedure CreateImage();
var
  Index, Width, Height: Integer;
begin
  Width := 0;
  Height := 0;
  for Index := 0 to 9 do
  begin
    if Images[Index].Width > Width then
      Width := Images[Index].Width;
    if Images[Index].Height > Height then
      Height := Images[Index].Height;
  end;
  Image := TBitmap.Create();
  Image.PixelFormat := Images[0].PixelFormat;
  Image.Width := Width * 9;
  Image.Height := Height;
end;

procedure PrintNumber(Number: Integer);
var
  Str: string;
  Index, X, Num: Integer;
begin
  with Image.Canvas do
  begin
    Brush.Style := bsSolid;
    Brush.Color := clWhite;
    Pen.Style := psClear;
    Pen.Color := clWhite;
    FillRect(Rect(0, 0, Image.Width, Image.Height));
  end;
  Str := '         ' + IntToStr(Number);
  X := Image.Width;
  Index := Length(Str);
  with Image.Canvas do
    repeat
      Num := Ord(Str[Index]) - Ord('0');
      Dec(X, Images[Num].Width);
      Draw(X, 0, Images[Num]);
      Dec(Index);
    until Str[Index] = ' ';
end;

procedure FreeAll();
var
  Index: Integer;
begin
  for Index := 0 to 9 do
    Images[Index].Free();
  for Index := 0 to 255 do
    Alpha[Index].Free();
  Image.Free();
  Papper.Free();
  avi_close();
end;

procedure VideoInit(Filename: string; Fps: Integer);
begin
  avi_settings(nil, Image, Fps, True);
  avi_create(Filename);
end;

procedure VideoFrame(Number: Integer = -1);
begin
  if Number >= 0 then
    PrintNumber(Number);
  avi_write(Image);
end;

procedure VideoEnd();
begin
  avi_close();
end;

procedure Main(Doc: string);
var
  Log: Text;
  Fps, Len, One, Two, Loop, Index, Width, Height: Integer;
  Next: Real;
  Line, Capt, Name, Ext: string;
begin
  if not FileExists(Doc) then
    Exit;
  Ext := LowerCase(ExtractFileExt(Doc));
  if (Ext <> '.log') and (Ext <> '.txt') then
    Exit;
  FileMode := 0;
  Assign(Log, Doc);
  try
    Reset(Log);
    if Ext = '.log' then
    begin

      while not Eof(Log) do
      begin
        Readln(Log, Line);
        if Line = '' then
          Continue;
        Width := 0;
        Height := 0;
        Name := '';
        for Index := 1 to Length(Line) do
        begin
          One := Ord(Line[Index]);
          Capt := IntToHex(One, 2);
          Name := Name + Capt;
          if Alpha[One] = nil then
          begin
            Capt := font_dir + Capt + '.bmp';
            if not FileExists(Capt) then
            begin
              Capt := AnsiUpperCase(Line[Index]);
              if Capt <> '' then
                Capt := font_dir + IntToHex(Ord(Capt[1]), 2) + '.bmp';
              if (Capt = '') or not FileExists(Capt) then
              begin
                Capt := font_dir + '00.bmp';
                if not FileExists(Capt) then
                  Continue;
              end;
            end;
            Alpha[One] := TBitmap.Create();
            Alpha[One].LoadFromFile(Capt);
            Alpha[One].PixelFormat := pf24bit;
          end;
          Inc(Width, Alpha[One].Width);
          if Alpha[One].Height > Height then
            Height := Alpha[One].Height;
        end;
        if Name = '' then
          Continue;
        if Papper = nil then
        begin
          Papper := TBitmap.Create();
          Papper.PixelFormat := pf24bit;
          Papper.Canvas.Pen.Style := psClear;
          Papper.Canvas.Brush.Color := clWhite;
        end;
        Papper.Width := Width;
        Papper.Height := Height;
        Papper.Canvas.FillRect(Rect(0, 0, Width, Height));
        Width := 0;
        for Index := 1 to Length(Line) do
        begin
          One := Ord(Line[Index]);
          Papper.Canvas.Draw(Width, 0, Alpha[One]);
          Inc(Width, Alpha[One].Width);
        end;
        Name := Copy(Name, 1, 16);
        Papper.SaveToFile(ChangeFileExt(Doc, '.' + Name + '.bmp'));
      end;

    end
    else
    begin

      if Image = nil then
      begin
        CollectImages();
        CreateImage();
      end;

      Readln(Log, Fps);
      VideoInit(Doc + '.avi', Fps);
      while not Eof(Log) do
      begin
        Readln(Log, Len, One, Two);
        Two := Two - One + 1;
        Next := One;
        for Loop := 1 to Len do
        begin
          VideoFrame(Round(Next - 0.5));
          Next := One + Two * Loop / (Len - 1);
        end;
      end;
      VideoEnd();

    end;
  finally
    Close(Log);
  end;
end;

var
  Par: Integer;

begin
  try
    SetCurrentDir(ExtractFilePath(ParamStr(0)));
    for Par := 1 to ParamCount do
    try
      Main(ParamStr(Par));
    except
    end;
    FreeAll();
  except
  end;
end.

