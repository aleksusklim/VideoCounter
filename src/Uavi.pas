unit Uavi;

// functions for AVI writing

interface

uses // VFW.pas isn't standard
  Windows, Graphics, Forms, Classes, SysUtils;

// there are two parts in this unit: public functions and theirs private helpers

// here is public:

function avi_create(Filename: string): Boolean;

function avi_settings(ParentForm: TForm; SampleFrame: TBitmap; FramesPerSecond:
  Integer; NoCodec: Boolean = False): Boolean;

function avi_write(frame: TBitmap): Boolean;

procedure avi_close();

implementation

uses
  VFW;

var
  LastUsedFile: string = ''; // to delete it if nothing was written
  NoCodecs: Boolean = False;

procedure BitmapDataAndSize(Bitmap: TBitmap; out Data: PChar; out Size: Integer);
var
  A0, A1, Ah: PChar;
  H: Integer;
begin
  Data := nil;
  Size := 0;
  if (Bitmap = nil) or (Bitmap.Height < 2) then
    Exit;
  H := Bitmap.Height;
  A0 := Bitmap.{%H-}ScanLine[0];
  A1 := Bitmap.{%H-}ScanLine[1];
  Ah := Bitmap.{%H-}ScanLine[H - 1];
  if A0 < Ah then
  begin
    Data := A0;
    Size := (A1 - A0) * H;
  end
  else
  begin
    Data := Ah;
    Size := (A0 - A1) * H;
  end;
end;

// now declaration of privates:
function AVIAPI_create(filename: PChar): LongBool; forward;

function AVIAPI_settings(hwnd: THandle; width, height, bits, imgsize, fps:
  Integer; framedata: Pointer): Integer; forward;

function AVIAPI_write(framedata: Pointer): LongBool; forward;

procedure AVIAPI_close(); forward;

// must be called after a successful avi_settings();
// starts recording into a file; only one at time is allowed:
function avi_create(Filename: string): Boolean;
begin
  if (Filename = '') or (FileExists(Filename) and not DeleteFile(Filename)) then
  begin // when can't create
    Result := False;
    Exit;
  end;
  try
    Result := AVIAPI_create(PChar(Filename)); // actual Result
    LastUsedFile := Filename; // save the name
  except
    AVIAPI_close(); // close if unexpected error
    Result := False;
  end;
end;

// finalize current video; can be safely called at any time:
procedure avi_close();
var
  TempStream: TFileStream; // to get size
begin
  AVIAPI_close(); // there is internal safe-check
  if LastUsedFile <> '' then
  try // want to check the size of resulting video
    TempStream := TFileStream.Create(LastUsedFile, fmOpenRead or fmShareDenyNone);
    if TempStream.Size = 0 then  // it's emply
    begin
      TempStream.Free;
      DeleteFile(LastUsedFile); // so remove it
    end
    else
      TempStream.Free;
  except // ignore errors
  end;
  LastUsedFile := '';
end;

// must be called first, stores image properties and
// displays the codec select dialog; also stores user settings for next avi_create() calls:
function avi_settings(ParentForm: TForm; SampleFrame: TBitmap; FramesPerSecond:
  Integer; NoCodec: Boolean = False): Boolean;
var
  Bits, Size, Res: Integer;
  HWND: THandle;
  Data: PChar;
begin
  NoCodecs := NoCodec;
  if SampleFrame.PixelFormat = pf24bit then // get color depth
    Bits := 24
  else if SampleFrame.PixelFormat = pf32bit then
    Bits := 32
  else
  begin // palette and others are not supported because not tested and anyway not used in SpyroTAS
    Result := False;
    Exit;
  end;
  BitmapDataAndSize(SampleFrame, Data, Size); // for now don't care about flipping in Lazarus
  if ParentForm = nil then
    HWND := 0 // can be called even without a form
  else
    HWND := ParentForm.Handle;
  Res := AVIAPI_settings(HWND, SampleFrame.Width, SampleFrame.Height, Bits, Size,
    FramesPerSecond, Data); // proper arguments
  if Res = 0 then // error, something is wrong
    WriteLn('Avi error: this codec is not working!');
  Result := (Res > 0); // false if user pressed "Cancel" or closed settings window
end;

var // actually, this must be separated from public, but oh that Lazarus...
  Bitmap: BITMAPINFOHEADER; // see below
  LazData: Pointer = nil; // see below
  BitmapInfo: TBITMAPINFO; // for GetDIBits()

// save next frame; the bitmap must be identical (dimensions and color) to that in avi_settings() call:

function avi_write(Frame: TBitmap): Boolean;
var
  First, Last: PChar; // scanlines
begin
  try // send data pointer
    First := Frame.{%H-}ScanLine[0];
    Last := Frame.{%H-}ScanLine[Frame.height - 1];
    if First > Last then
      Result := AVIAPI_write(Last) // Delphi case
    else
    begin // Lazarus case, need to flip the image
      GetDIBits(Frame.Canvas.Handle, Frame.Handle, 0, Frame.Height, LazData,
        BitmapInfo, DIB_RGB_COLORS);
      Result := AVIAPI_write(LazData);
    end;
  except
    avi_close(); // probably access violation
    Result := False;
  end;
end;

// implementation of private part

var
  Configured: Boolean = False; // do we have valid settings
  Recording: Boolean = False; // was a recording started
  Datasize: Integer; // size of every frame in bytes
  Timepos: Integer; // tracks current frame position
  Avifile: IAVIFile = nil; // avi interface
  Mainstream: IAVIStream = nil; // unencrypted stream
  Targetstream: IAVIStream = nil; // stream with codec
  Stream: TAVIStreamInfo; // stream properties
  Options: TAVICOMPRESSOPTIONS; // encoder properties
  // Bitmap: BITMAPINFOHEADER; // image properties
  // LazData: Pointer = nil; // bitmap data buffer, for Lazarus

procedure AVIAPI_close();
begin
  if LazData <> nil then
    FreeMem(LazData); // free buffer
  LazData := nil;

// don't need to manually free interfaces since the compiler will do it for us:

//  if targetstream <> nil then AVIStreamClose(targetstream);
//  if mainstream <> nil then AVIStreamClose(mainstream);
//  if avifile <> nil then AVIFileClose(avifile);

// just null them, there will be invisible _Release() or something...
  if Targetstream <> nil then
    Targetstream := nil;
  if Mainstream <> nil then
    Mainstream := nil;
  if Avifile <> nil then
    Avifile := nil;

  if Recording then // close avi library if opened
    AVIFileExit();
  Recording := False;
end;

function AVIAPI_create(filename: PChar): LongBool;
begin
  Result := False;
  if not Configured and not NoCodecs then // must be prepared
    Exit;
  if Recording then // finalize revious video
    AVIAPI_close();
  AVIFileInit(); // init the library
  Recording := True;
  Timepos := 0; // beginning
  if AVIFileOpen(Avifile, filename, OF_WRITE or OF_CREATE, nil) <> AVIERR_OK then
    Exit; // something is probably wrong with the name
  if NoCodecs then
  begin
    if (AVIFileCreateStream(Avifile, Mainstream, Stream) <> AVIERR_OK) or (AVIStreamSetFormat
      (Mainstream, 0, @Bitmap, Bitmap.biSize) <> AVIERR_OK) then
    begin
      AVIAPI_close();
      Exit;
    end;
  end
  else if (AVIFileCreateStream(Avifile, Mainstream, Stream) <> AVIERR_OK) or (AVIMakeCompressedStream
    (Targetstream, Mainstream, @Options, nil) <> AVIERR_OK) or (AVIStreamSetFormat
    (Targetstream, 0, @Bitmap, Bitmap.biSize) <> AVIERR_OK) then
  begin // chain of calls
    AVIAPI_close();
    Exit; // if any was failed
  end;
  GetMem(LazData, Datasize); // this is for flipping images in Lazarus
  result := True;
end;

function AVIAPI_write(framedata: Pointer): LongBool;
begin
  Result := False;
  if not Recording then // must be configured and started
    Exit;
  if NoCodecs then
  begin
    if AVIStreamWrite(Mainstream, Timepos, 1, framedata, Datasize,
      AVIIF_KEYFRAME, nil, nil) <> AVIERR_OK then
    begin
      AVIAPI_close();
      Exit;
    end;
  end
  else if AVIStreamWrite(Targetstream, Timepos, 1, framedata, Datasize,
    AVIIF_KEYFRAME, nil, nil) <> AVIERR_OK then // write!
  begin
    AVIAPI_close();
    Exit; // an error during writing
  end;
  Inc(Timepos); // frame done
  Result := True;
end;

function AVIAPI_settings(hwnd: THandle; width, height, bits, imgsize, fps:
  Integer; framedata: Pointer): Integer;
var // these are temporaries that would be stored to globals on succerss
  bitmap_: BITMAPINFOHEADER;
  stream_: TAVISTREAMINFO;
  options_: TAVICOMPRESSOPTIONS;
  optionsarr: PAVICOMPRESSOPTIONS;
begin
  Result := 0;
  if Recording then // can't be called if recording was started
    Exit;
  if not NoCodecs then
  begin
    AVIFileInit();
    Recording := True; // temporary
    if (AVIFileOpen(Avifile, PChar('nul.avi'), OF_WRITE or OF_CREATE, nil) <>
      AVIERR_OK) // this is a little hack with an illegal name to suppress the file creation
      then
    begin
      AVIFileExit(); // something is really wrong
      Exit;
    end;
  end;
  // zero structs
  FillChar(bitmap_{%H-}, SizeOf(BITMAPINFOHEADER), 0);
  FillChar(stream_{%H-}, SizeOf(TAVISTREAMINFO), 0);
  FillChar(options_{%H-}, SizeOf(TAVICOMPRESSOPTIONS), 0);
  // stream settings
  stream_.fccType := streamtypeVIDEO;
  stream_.fccHandler := 0;
  stream_.dwScale := 1;
  stream_.dwRate := fps;
  stream_.dwSuggestedBufferSize := imgsize;
  SetRect(stream_.rcFrame, 0, 0, width, height);
  // bitmap settings
  bitmap_.biSize := sizeof(BITMAPINFOHEADER);
  bitmap_.biWidth := width;
  bitmap_.biHeight := height;
  bitmap_.biPlanes := 1;
  bitmap_.biBitCount := bits;
  bitmap_.biCompression := BI_RGB;
  optionsarr := @options_;
  if not NoCodecs then
  begin
    if AVIFileCreateStream(Avifile, Mainstream, stream_) <> AVIERR_OK then
    begin // failed
      AVIAPI_close();
      Exit;
    end;
  // most important - show codec dialod
    if not AVISaveOptions(hwnd, 0, 1, Mainstream, optionsarr) then
    begin
      AVISaveOptionsFree(1, optionsarr);
      AVIAPI_close();
      Result := -1; // user cancelled
      Exit;
    end;
    AVISaveOptionsFree(1, optionsarr); // chain following; also try to write a frame
    if (AVIMakeCompressedStream(Targetstream, Mainstream, optionsarr, nil) <>
      AVIERR_OK) or (AVIStreamSetFormat(Targetstream, 0, @bitmap_, bitmap_.biSize)
      <> AVIERR_OK) or (AVIStreamWrite(Targetstream, 0, 1, framedata, imgsize,
      AVIIF_KEYFRAME, nil, nil) <> AVIERR_OK) then
    begin // if unsupported
      AVIAPI_close();
      Exit;
    end;
  end;
  // store selected settings
  Stream := stream_;
  Bitmap := bitmap_;
  BitmapInfo.bmiHeader := Bitmap;
  Options := options_;
  Datasize := imgsize;
  Configured := True;
  if not NoCodecs then
    AVIAPI_close(); // closing even at success
  Result := 1;
end;

end.

// EOF

//(no codec for SpyroTAS?)


