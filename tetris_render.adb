--  Tetris_Render body.
with Ada.Characters.Latin_1;
with Ada.Environment_Variables;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Interfaces.C;

package body Tetris_Render is
   use type Tetris_Model.Piece_Kind;

   use Interfaces.C;
   use type SDL.SDL_Renderer_Ptr;
   use type SDL.SDL_Surface_Ptr;
   use type SDL.SDL_Texture_Ptr;
   use type SDL_TTF.TTF_Font_Ptr;

   White : constant Tetris_Model.RGB := (235, 235, 240);
   Dim   : constant Tetris_Model.RGB := (150, 150, 160);

   function To_Color (C : Tetris_Model.RGB) return SDL.SDL_Color is
     (SDL.SDL_Color'(SDL.Uint8 (C.R), SDL.Uint8 (C.G), SDL.Uint8 (C.B), 255));

   function Lighten (C : Tetris_Model.RGB; By : Integer) return Tetris_Model.RGB is
      function L (V : Natural) return Natural is
      begin
         if V + By > 255 then
            return 255;
         end if;
         return V + By;
      end L;
   begin
      return (L (C.R), L (C.G), L (C.B));
   end Lighten;

   procedure Fill_Rect
     (Ren : SDL.SDL_Renderer_Ptr; X, Y, W, H : Integer;
      C : Tetris_Model.RGB; A : SDL.Uint8 := 255)
   is
      R     : aliased SDL.SDL_Rect :=
        (Interfaces.C.int (X), Interfaces.C.int (Y),
         Interfaces.C.int (W), Interfaces.C.int (H));
      Dummy : Interfaces.C.int;
      pragma Unreferenced (Dummy);
   begin
      Dummy := SDL.SDL_SetRenderDrawColor
        (Ren, SDL.Uint8 (C.R), SDL.Uint8 (C.G), SDL.Uint8 (C.B), A);
      Dummy := SDL.SDL_RenderFillRect (Ren, R'Access);
   end Fill_Rect;

   procedure Frame_Rect
     (Ren : SDL.SDL_Renderer_Ptr; X, Y, W, H : Integer; C : Tetris_Model.RGB)
   is
      R     : aliased SDL.SDL_Rect :=
        (Interfaces.C.int (X), Interfaces.C.int (Y),
         Interfaces.C.int (W), Interfaces.C.int (H));
      Dummy : Interfaces.C.int;
      pragma Unreferenced (Dummy);
   begin
      Dummy := SDL.SDL_SetRenderDrawColor
        (Ren, SDL.Uint8 (C.R), SDL.Uint8 (C.G), SDL.Uint8 (C.B), 255);
      Dummy := SDL.SDL_RenderDrawRect (Ren, R'Access);
   end Frame_Rect;

   procedure Draw_Cell
     (Ren : SDL.SDL_Renderer_Ptr; Col, Row : Integer; C : Tetris_Model.RGB)
   is
      X : constant Integer := Col * Cell_Size;
      Y : constant Integer := Row * Cell_Size;
   begin
      Fill_Rect (Ren, X, Y, Cell_Size, Cell_Size, C);
      Fill_Rect (Ren, X + 2, Y + 2, Cell_Size - 4, Cell_Size - 4, Lighten (C, 45));
   end Draw_Cell;

   procedure Draw_Text
     (Ren  : SDL.SDL_Renderer_Ptr;
      Font : SDL_TTF.TTF_Font_Ptr;
      X, Y : Integer; Text : String; C : Tetris_Model.RGB)
   is
      Surf  : SDL.SDL_Surface_Ptr;
      Tex   : SDL.SDL_Texture_Ptr;
      Dummy : Interfaces.C.int;
      pragma Unreferenced (Dummy);
      Fmt   : aliased SDL.Uint32;
      Acc   : aliased Interfaces.C.int;
      W, H  : aliased Interfaces.C.int;
      Dst   : aliased SDL.SDL_Rect;
   begin
      if Font = null then
         return;
      end if;
      Surf := SDL_TTF.TTF_RenderUTF8_Solid (Font, To_C (Text), To_Color (C));
      if Surf = null then
         return;
      end if;
      Tex := SDL.SDL_CreateTextureFromSurface (Ren, Surf);
      if Tex = null then
         SDL.SDL_FreeSurface (Surf);
         return;
      end if;
      Dummy := SDL.SDL_QueryTexture (Tex, Fmt'Access, Acc'Access, W'Access, H'Access);
      Dst := (Interfaces.C.int (X), Interfaces.C.int (Y), W, H);
      Dummy := SDL.SDL_RenderCopy (Ren, Tex, null, Dst'Access);
      SDL.SDL_DestroyTexture (Tex);
      SDL.SDL_FreeSurface (Surf);
   end Draw_Text;

   procedure Draw_Preview
     (Ren : SDL.SDL_Renderer_Ptr; K : Tetris_Model.Piece_Kind;
      X, Y, Pc : Integer)
   is
   begin
      if K = Tetris_Model.None then
         return;
      end if;
      declare
         D   : constant Tetris_Model.Piece_Def := Tetris_Model.Def (K);
         Cs  : constant Tetris_Model.Cells := Tetris_Model.Cells_Of (K, 0);
         Off : constant Integer := (4 - D.Size) * Pc / 2;
      begin
         for C of Cs loop
            Fill_Rect (Ren, X + Off + C.X * Pc, Y + Off + C.Y * Pc,
                       Pc - 2, Pc - 2, D.Color);
         end loop;
      end;
   end Draw_Preview;

   procedure Draw
     (Ren : SDL.SDL_Renderer_Ptr; Fonts : Font_Set; G : Tetris_Model.Game_State)
   is
      use Tetris_Model;
      Panel_X : constant Integer := Board_Pixel_Width + 24;
      Pc      : constant := 18;   --  preview cell size
      Dummy   : Interfaces.C.int;
      pragma Unreferenced (Dummy);
   begin
      Dummy := SDL.SDL_RenderClear (Ren);
      Fill_Rect (Ren, 0, 0, Window_Width, Window_Height, (16, 16, 22));

      --  grid
      for I in 0 .. Cols loop
         Fill_Rect (Ren, I * Cell_Size, 0, 1, Board_Pixel_Height, (28, 28, 38));
      end loop;
      for I in 0 .. Rows loop
         Fill_Rect (Ren, 0, I * Cell_Size, Board_Pixel_Width, 1, (28, 28, 38));
      end loop;

      --  locked cells
      for R in 0 .. Rows - 1 loop
         for C in 0 .. Cols - 1 loop
            if G.Board (R) (C) /= None then
               Draw_Cell (Ren, C, R, Def (G.Board (R) (C)).Color);
            end if;
         end loop;
      end loop;
      Frame_Rect (Ren, 0, 0, Board_Pixel_Width, Board_Pixel_Height, (90, 90, 110));

      if not G.Over then
         --  ghost piece
         declare
            Gy : Integer := G.Y;
         begin
            while not Collides (G, G.Current, G.Rot, G.X, Gy + 1) loop
               Gy := Gy + 1;
            end loop;
            if Gy /= G.Y then
               for C of Cells_Of (G.Current, G.Rot) loop
                  declare
                     BX : constant Integer := G.X + C.X;
                     BY : constant Integer := Gy + C.Y;
                  begin
                     if BY >= 0 then
                        Frame_Rect (Ren, BX * Cell_Size + 1, BY * Cell_Size + 1,
                                    Cell_Size - 2, Cell_Size - 2,
                                    Def (G.Current).Color);
                     end if;
                  end;
               end loop;
            end if;
         end;
         --  falling piece
         for C of Cells_Of (G.Current, G.Rot) loop
            declare
               BX : constant Integer := G.X + C.X;
               BY : constant Integer := G.Y + C.Y;
            begin
               if BY >= 0 then
                  Draw_Cell (Ren, BX, BY, Def (G.Current).Color);
               end if;
            end;
         end loop;
      end if;

      --  side panel
      Draw_Text (Ren, Fonts.Small, Panel_X, 16, "SCORE", Dim);
      Draw_Text (Ren, Fonts.Med, Panel_X, 36, G.Score'Img, White);
      Draw_Text (Ren, Fonts.Small, Panel_X, 92, "LINES", Dim);
      Draw_Text (Ren, Fonts.Med, Panel_X, 112, G.Lines'Img, White);
      Draw_Text (Ren, Fonts.Small, Panel_X, 168, "LEVEL", Dim);
      Draw_Text (Ren, Fonts.Med, Panel_X, 188, G.Level'Img, White);

      Draw_Text (Ren, Fonts.Small, Panel_X, 244, "NEXT", Dim);
      Fill_Rect (Ren, Panel_X - 6, 264, 4 * Pc + 12, 4 * Pc + 12, (24, 24, 32));
      Frame_Rect (Ren, Panel_X - 6, 264, 4 * Pc + 12, 4 * Pc + 12, (70, 70, 90));
      Draw_Preview (Ren, Peek_Next (G), Panel_X, 270, Pc);

      Draw_Text (Ren, Fonts.Small, Panel_X, 368, "HOLD", Dim);
      Fill_Rect (Ren, Panel_X - 6, 388, 4 * Pc + 12, 4 * Pc + 12, (24, 24, 32));
      Frame_Rect (Ren, Panel_X - 6, 388, 4 * Pc + 12, 4 * Pc + 12, (70, 70, 90));
      Draw_Preview (Ren, G.Hold, Panel_X, 394, Pc);

      Draw_Text (Ren, Fonts.Small, Panel_X, 500, "Arrows move/drop", Dim);
      Draw_Text (Ren, Fonts.Small, Panel_X, 520, "Up/X rot, Z ccw", Dim);
      Draw_Text (Ren, Fonts.Small, Panel_X, 540, "Space hard drop", Dim);
      Draw_Text (Ren, Fonts.Small, Panel_X, 560, "C hold, P pause", Dim);
      Draw_Text (Ren, Fonts.Small, Panel_X, 580, "R restart, Esc quit", Dim);

      --  overlays
      if G.Over or else G.Paused then
         Fill_Rect (Ren, 0, 0, Board_Pixel_Width, Board_Pixel_Height, (0, 0, 0), 170);
         if G.Over then
            Draw_Text (Ren, Fonts.Big, 60, Board_Pixel_Height / 2 - 60,
                       "GAME OVER", (255, 80, 80));
            Draw_Text (Ren, Fonts.Med, 82, Board_Pixel_Height / 2 - 10,
                       "Score" & G.Score'Img, White);
            Draw_Text (Ren, Fonts.Small, 79, Board_Pixel_Height / 2 + 34,
                       "Press R to restart", Dim);
         else
            Draw_Text (Ren, Fonts.Big, 95, Board_Pixel_Height / 2 - 20,
                       "PAUSED", White);
         end if;
      end if;

      SDL.SDL_RenderPresent (Ren);
   end Draw;

   procedure Dump_PPM (Ren : SDL.SDL_Renderer_Ptr; Path : String) is
      use Ada.Streams.Stream_IO;
      type Byte_Array is array (Natural range <>) of SDL.Uint8;
      type Byte_Array_Ptr is access Byte_Array;
      N   : constant Natural := Window_Width * Window_Height * 4;
      Buf : constant Byte_Array_Ptr := new Byte_Array (0 .. N - 1);
      Res : Interfaces.C.int;
      File : File_Type;
      Header : constant String :=
        "P6" & Ada.Characters.Latin_1.LF
        & Window_Width'Img & " " & Window_Height'Img & Ada.Characters.Latin_1.LF
        & "255" & Ada.Characters.Latin_1.LF;
   begin
      Res := SDL.SDL_RenderReadPixels
        (Ren, null, SDL.SDL_PIXELFORMAT_ARGB8888, Buf.all'Address,
         Interfaces.C.int (Window_Width * 4));
      if Res /= 0 then
         Ada.Text_IO.Put_Line
           ("RenderReadPixels failed: " & To_Ada (SDL.SDL_GetError));
         return;
      end if;
      Create (File, Out_File, Path);
      String'Write (Stream (File), Header);
      for I in 0 .. Window_Width * Window_Height - 1 loop
         --  ARGB8888 in memory (little-endian) is B,G,R,A
         SDL.Uint8'Write (Stream (File), Buf (I * 4 + 2));  --  R
         SDL.Uint8'Write (Stream (File), Buf (I * 4 + 1));  --  G
         SDL.Uint8'Write (Stream (File), Buf (I * 4 + 0));  --  B
      end loop;
      Close (File);
   end Dump_PPM;

   function Find_Font return Ada.Strings.Unbounded.Unbounded_String is
      use Ada.Strings.Unbounded;
      Env : constant String :=
        (if Ada.Environment_Variables.Exists ("TETRIS_FONT")
         then Ada.Environment_Variables.Value ("TETRIS_FONT")
         else "");
      Candidates : constant array (1 .. 5) of Unbounded_String :=
        (To_Unbounded_String (Env),
         To_Unbounded_String ("/usr/share/fonts/Adwaita/AdwaitaMono-Bold.ttf"),
         To_Unbounded_String ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"),
         To_Unbounded_String ("/usr/share/fonts/noto/NotoSans-Bold.ttf"),
         To_Unbounded_String ("/usr/share/fonts/TTF/DejaVuSans-Bold.ttf"));
   begin
      for C of Candidates loop
         if Length (C) > 0 then
            declare
               F : constant SDL_TTF.TTF_Font_Ptr :=
                 SDL_TTF.TTF_OpenFont (To_C (To_String (C)), 22);
            begin
               if F /= null then
                  SDL_TTF.TTF_CloseFont (F);
                  return C;
               end if;
            end;
         end if;
      end loop;
      return To_Unbounded_String ("");
   end Find_Font;

   procedure Open_Fonts (Path : String; Fonts : out Font_Set) is
   begin
      Fonts.Small := SDL_TTF.TTF_OpenFont (To_C (Path), 15);
      Fonts.Med   := SDL_TTF.TTF_OpenFont (To_C (Path), 22);
      Fonts.Big   := SDL_TTF.TTF_OpenFont (To_C (Path), 36);
   end Open_Fonts;

   procedure Close_Fonts (Fonts : in out Font_Set) is
   begin
      if Fonts.Small /= null then SDL_TTF.TTF_CloseFont (Fonts.Small); end if;
      if Fonts.Med /= null then SDL_TTF.TTF_CloseFont (Fonts.Med); end if;
      if Fonts.Big /= null then SDL_TTF.TTF_CloseFont (Fonts.Big); end if;
   end Close_Fonts;

end Tetris_Render;
