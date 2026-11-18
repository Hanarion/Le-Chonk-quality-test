--  Tetris in Ada, rendered with SDL2.
--
--  Controls: Left/Right move (with DAS auto-repeat), Down soft drop,
--  Up or X rotate CW, Z rotate CCW, Space hard drop, C hold, P pause,
--  R restart, Esc quit.
--
--  Headless test hooks (env vars):
--    TETRIS_DEMO=N     run N frames with scripted input, dump
--                      tetris_demo.ppm (via SDL_RenderReadPixels), print
--                      final score/lines, then exit
--    TETRIS_SEED=S     fixed RNG seed (default: from the clock)
--    TETRIS_PRELOAD=1  pre-fill the bottom row except column 9 and spawn
--                      a vertical I piece, so the scripted hard drop
--                      clears a line (verifies Clear_Lines + scoring)
--    TETRIS_FONT=path  override the font file
with Ada.Calendar;
with Ada.Characters.Latin_1;
with Ada.Environment_Variables;
with Ada.Numerics.Discrete_Random;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces.C;
with SDL;

procedure Tetris is

   use Interfaces.C;
   use type SDL.SDL_Window_Ptr;
   use type SDL.SDL_Renderer_Ptr;
   use type SDL.SDL_Surface_Ptr;
   use type SDL.SDL_Texture_Ptr;
   use type SDL.TTF_Font_Ptr;

   --  geometry --------------------------------------------------------------
   Cols    : constant := 10;
   Rows    : constant := 20;
   Cell    : constant := 32;                 --  board cell, px
   Board_W : constant := Cols * Cell;        --  320
   Board_H : constant := Rows * Cell;        --  640
   Panel_W : constant := 220;
   Win_W   : constant := Board_W + Panel_W;  --  540
   Win_H   : constant := Board_H;            --  640

   type RGB is record
      R, G, B : SDL.Uint8;
   end record;

   White : constant RGB := (235, 235, 240);
   Dim   : constant RGB := (150, 150, 160);

   --  pieces ----------------------------------------------------------------
   type Piece_Kind is (None, I_P, O_P, T_P, S_P, Z_P, J_P, L_P);
   subtype Cell_Kind is Piece_Kind;
   subtype Real_Kind is Piece_Kind range I_P .. L_P;

   type Coord is record
      X, Y : Integer;
   end record;

   type Cells is array (1 .. 4) of Coord;

   type Piece_Def is record
      Size  : Integer;   --  bounding box 2, 3 or 4
      Base  : Cells;     --  cells in rotation state 0
      Color : RGB;
   end record;

   Piece_Defs : constant array (Piece_Kind) of Piece_Def :=
     (None => (2, ((0, 0), (0, 0), (0, 0), (0, 0)), (0, 0, 0)),
      I_P  => (4, ((0, 1), (1, 1), (2, 1), (3, 1)), (0, 240, 240)),
      O_P  => (2, ((0, 0), (1, 0), (0, 1), (1, 1)), (240, 240, 0)),
      T_P  => (3, ((1, 0), (0, 1), (1, 1), (2, 1)), (170, 0, 240)),
      S_P  => (3, ((1, 0), (2, 0), (0, 1), (1, 1)), (0, 230, 0)),
      Z_P  => (3, ((0, 0), (1, 0), (1, 1), (2, 1)), (240, 0, 0)),
      J_P  => (3, ((0, 0), (0, 1), (1, 1), (2, 1)), (0, 0, 240)),
      L_P  => (3, ((2, 0), (0, 1), (1, 1), (2, 1)), (240, 160, 0)));

   --  board -----------------------------------------------------------------
   type Row_Type is array (0 .. Cols - 1) of Cell_Kind;
   type Board_Type is array (0 .. Rows - 1) of Row_Type;

   subtype Seven is Integer range 1 .. 7;
   package Seven_Rand is new Ada.Numerics.Discrete_Random (Seven);

   type Bag_Type is array (Seven) of Real_Kind;

   type Game_State is record
      Board     : Board_Type := (others => (others => None));
      Current   : Real_Kind := T_P;
      Hold      : Piece_Kind := None;
      Can_Hold  : Boolean := True;
      X, Y      : Integer := 0;
      Rot       : Natural := 0;
      Bag       : Bag_Type := (others => I_P);
      Bag_Idx   : Natural := 8;   --  forces a refill on first spawn
      Score     : Natural := 0;
      Lines     : Natural := 0;
      Level     : Natural := 1;
      Drop_Acc  : SDL.Uint32 := 0;
      Over      : Boolean := False;
      Paused    : Boolean := False;
   end record;

   Kicks : constant array (1 .. 6) of Coord :=
     ((0, 0), (-1, 0), (1, 0), (0, -1), (-2, 0), (2, 0));

   --  globals shared with the nested helpers --------------------------------
   Gen         : Seven_Rand.Generator;
   St          : Game_State;
   Ren         : SDL.SDL_Renderer_Ptr;
   Font_Small  : SDL.TTF_Font_Ptr;
   Font_Med    : SDL.TTF_Font_Ptr;
   Font_Big    : SDL.TTF_Font_Ptr;
   Preload     : Boolean := False;
   Left_Held   : Boolean := False;
   Right_Held  : Boolean := False;
   Down_Held   : Boolean := False;
   Dir         : Integer := 0;               --  DAS direction: -1, 0, +1
   Move_Start  : SDL.Uint32 := 0;
   Last_Arr    : SDL.Uint32 := 0;

   Das_Delay : constant SDL.Uint32 := 150;   --  ms before auto-repeat starts
   Arr_Delay : constant SDL.Uint32 := 40;    --  ms between auto-repeats

   type Action is (Move_L, Move_R, Rot_CW, Rot_CCW, Hard, Hold_A);

   function Playing return Boolean is (not St.Over and then not St.Paused);

   --  pieces ----------------------------------------------------------------
   function Cells_Of (K : Real_Kind; Rot : Natural) return Cells is
      D  : constant Piece_Def := Piece_Defs (K);
      Cs : Cells := D.Base;
   begin
      for I in 1 .. Rot mod 4 loop
         for C of Cs loop
            declare
               Old : constant Coord := C;
            begin
               C := (X => D.Size - 1 - Old.Y, Y => Old.X);  --  CW on screen
            end;
         end loop;
      end loop;
      return Cs;
   end Cells_Of;

   function Collides
     (G : Game_State; K : Real_Kind; Rot : Natural; X, Y : Integer) return Boolean
   is
      Cs : constant Cells := Cells_Of (K, Rot);
   begin
      for C of Cs loop
         declare
            BX : constant Integer := X + C.X;
            BY : constant Integer := Y + C.Y;
         begin
            if BY >= Rows then
               return True;
            end if;
            if BY >= 0
              and then (BX < 0 or else BX >= Cols
                        or else G.Board (BY) (BX) /= None)
            then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Collides;

   procedure Refill_Bag (G : in out Game_State) is
      Kinds : constant Bag_Type := (I_P, O_P, T_P, S_P, Z_P, J_P, L_P);
   begin
      G.Bag := Kinds;
      for I in reverse 2 .. 7 loop
         declare
            J   : constant Seven := Seven_Rand.Random (Gen);
            Tmp : constant Real_Kind := G.Bag (I);
         begin
            G.Bag (I) := G.Bag (J);
            G.Bag (J) := Tmp;
         end;
      end loop;
      G.Bag_Idx := 1;
   end Refill_Bag;

   function Peek_Next (G : Game_State) return Real_Kind is
   begin
      if G.Bag_Idx > 7 then
         return G.Bag (1);
      end if;
      return G.Bag (G.Bag_Idx);
   end Peek_Next;

   procedure Spawn (G : in out Game_State) is
   begin
      if G.Bag_Idx > 7 then
         Refill_Bag (G);
      end if;
      G.Current := G.Bag (G.Bag_Idx);
      G.Bag_Idx := G.Bag_Idx + 1;
      G.Rot := 0;
      G.X := (Cols - Piece_Defs (G.Current).Size) / 2;
      G.Y := (if G.Current = I_P then -1 else 0);
      G.Can_Hold := True;
      if Collides (G, G.Current, 0, G.X, G.Y) then
         G.Over := True;
      end if;
   end Spawn;

   procedure Clear_Lines (G : in out Game_State) is
      R       : Integer := Rows - 1;
      Cleared : Natural := 0;
   begin
      while R >= 0 loop
         declare
            Full : Boolean := True;
         begin
            for C in 0 .. Cols - 1 loop
               if G.Board (R) (C) = None then
                  Full := False;
                  exit;
               end if;
            end loop;
            if Full then
               for RR in reverse 1 .. R loop
                  G.Board (RR) := G.Board (RR - 1);
               end loop;
               G.Board (0) := (others => None);
               Cleared := Cleared + 1;
            else
               R := R - 1;
            end if;
         end;
      end loop;
      if Cleared > 0 then
         declare
            Points : constant Natural :=
              (case Cleared is
                 when 1      => 100,
                 when 2      => 300,
                 when 3      => 500,
                 when others => 800);
         begin
            G.Score := G.Score + Points * G.Level;
            G.Lines := G.Lines + Cleared;
            G.Level := G.Lines / 10 + 1;
         end;
      end if;
   end Clear_Lines;

   procedure Lock_Piece (G : in out Game_State) is
      Cs : constant Cells := Cells_Of (G.Current, G.Rot);
   begin
      for C of Cs loop
         declare
            BX : constant Integer := G.X + C.X;
            BY : constant Integer := G.Y + C.Y;
         begin
            if BY < 0 then
               G.Over := True;               --  locked above the visible field
            else
               G.Board (BY) (BX) := G.Current;
            end if;
         end;
      end loop;
      if not G.Over then
         Clear_Lines (G);
         Spawn (G);
      end if;
   end Lock_Piece;

   function Try_Move (G : in out Game_State; DX, DY : Integer) return Boolean is
   begin
      if not Collides (G, G.Current, G.Rot, G.X + DX, G.Y + DY) then
         G.X := G.X + DX;
         G.Y := G.Y + DY;
         return True;
      end if;
      return False;
   end Try_Move;

   function Try_Rotate (G : in out Game_State; Dir : Natural) return Boolean is
      New_Rot : constant Natural := (G.Rot + Dir) mod 4;
   begin
      for K of Kicks loop
         if not Collides (G, G.Current, New_Rot, G.X + K.X, G.Y + K.Y) then
            G.Rot := New_Rot;
            G.X := G.X + K.X;
            G.Y := G.Y + K.Y;
            return True;
         end if;
      end loop;
      return False;
   end Try_Rotate;

   procedure Step_Down (G : in out Game_State) is
   begin
      if not Try_Move (G, 0, 1) then
         Lock_Piece (G);
      end if;
   end Step_Down;

   procedure Hard_Drop (G : in out Game_State) is
      Dist : Natural := 0;
   begin
      while not Collides (G, G.Current, G.Rot, G.X, G.Y + Dist + 1) loop
         Dist := Dist + 1;
      end loop;
      G.Y := G.Y + Dist;
      G.Score := G.Score + 2 * Dist;
      Lock_Piece (G);
   end Hard_Drop;

   procedure Hold_Piece (G : in out Game_State) is
   begin
      if not G.Can_Hold or else G.Over then
         return;
      end if;
      if G.Hold = None then
         G.Hold := G.Current;
         Spawn (G);
      else
         declare
            T : constant Real_Kind := Real_Kind (G.Hold);
         begin
            G.Hold := G.Current;
            G.Current := T;
            G.Rot := 0;
            G.X := (Cols - Piece_Defs (T).Size) / 2;
            G.Y := (if T = I_P then -1 else 0);
            if Collides (G, G.Current, 0, G.X, G.Y) then
               G.Over := True;
            end if;
         end;
      end if;
      G.Can_Hold := False;
   end Hold_Piece;

   function Drop_Interval (Level : Natural) return SDL.Uint32 is
      F : constant Float := 1000.0 * 0.85 ** (Level - 1);
   begin
      if F < 50.0 then
         return 50;
      end if;
      return SDL.Uint32 (Integer (F));
   end Drop_Interval;

   procedure Do_Action (A : Action) is
   begin
      if not Playing then
         return;
      end if;
      case A is
         when Move_L  => if Try_Move (St, -1, 0) then null; end if;
         when Move_R  => if Try_Move (St, 1, 0) then null; end if;
         when Rot_CW  => if Try_Rotate (St, 1) then null; end if;
         when Rot_CCW => if Try_Rotate (St, 3) then null; end if;
         when Hard    => Hard_Drop (St);
         when Hold_A  => Hold_Piece (St);
      end case;
   end Do_Action;

   procedure New_Game (G : in out Game_State) is
   begin
      G := (others => <>);
      Left_Held := False;
      Right_Held := False;
      Down_Held := False;
      Dir := 0;
      Refill_Bag (G);
      if Preload then
         --  bottom row filled except column 9; the bag starts with I
         for C in 0 .. Cols - 2 loop
            G.Board (Rows - 1) (C) := Z_P;
         end loop;
         G.Bag := (I_P, O_P, T_P, S_P, Z_P, J_P, L_P);
         G.Bag_Idx := 1;
      end if;
      Spawn (G);
   end New_Game;

   --  drawing ---------------------------------------------------------------
   function Lighten (C : RGB; By : Integer) return RGB is
      function L (V : SDL.Uint8) return SDL.Uint8 is
      begin
         if Natural (V) + By > 255 then
            return 255;
         end if;
         return SDL.Uint8 (Natural (V) + By);
      end L;
   begin
      return (L (C.R), L (C.G), L (C.B));
   end Lighten;

   procedure Fill_Rect (X, Y, W, H : Integer; C : RGB; A : SDL.Uint8 := 255) is
      R     : aliased SDL.SDL_Rect :=
        (Interfaces.C.int (X), Interfaces.C.int (Y),
         Interfaces.C.int (W), Interfaces.C.int (H));
      Dummy : Interfaces.C.int;
      pragma Unreferenced (Dummy);
   begin
      Dummy := SDL.SDL_SetRenderDrawColor (Ren, C.R, C.G, C.B, A);
      Dummy := SDL.SDL_RenderFillRect (Ren, R'Access);
   end Fill_Rect;

   procedure Frame_Rect (X, Y, W, H : Integer; C : RGB) is
      R     : aliased SDL.SDL_Rect :=
        (Interfaces.C.int (X), Interfaces.C.int (Y),
         Interfaces.C.int (W), Interfaces.C.int (H));
      Dummy : Interfaces.C.int;
      pragma Unreferenced (Dummy);
   begin
      Dummy := SDL.SDL_SetRenderDrawColor (Ren, C.R, C.G, C.B, 255);
      Dummy := SDL.SDL_RenderDrawRect (Ren, R'Access);
   end Frame_Rect;

   procedure Draw_Cell (Col, Row : Integer; C : RGB) is
      X : constant Integer := Col * Cell;
      Y : constant Integer := Row * Cell;
   begin
      Fill_Rect (X, Y, Cell, Cell, C);
      Fill_Rect (X + 2, Y + 2, Cell - 4, Cell - 4, Lighten (C, 45));
   end Draw_Cell;

   procedure Draw_Text
     (Font : SDL.TTF_Font_Ptr; X, Y : Integer; Text : String; C : RGB)
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
      Surf := SDL.TTF_RenderUTF8_Solid
        (Font, To_C (Text), SDL.SDL_Color'(C.R, C.G, C.B, 255));
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

   procedure Draw_Preview (K : Piece_Kind; X, Y, Pc : Integer) is
   begin
      if K = None then
         return;
      end if;
      declare
         D  : constant Piece_Def := Piece_Defs (K);
         Cs : constant Cells := Cells_Of (K, 0);
         Off : constant Integer := (4 - D.Size) * Pc / 2;
      begin
         for C of Cs loop
            Fill_Rect (X + Off + C.X * Pc, Y + Off + C.Y * Pc, Pc - 2, Pc - 2, D.Color);
         end loop;
      end;
   end Draw_Preview;

   procedure Render (G : Game_State) is
      Panel_X : constant Integer := Board_W + 24;
      Pc      : constant := 18;   --  preview cell size
      Dummy   : Interfaces.C.int;
      pragma Unreferenced (Dummy);
   begin
      Dummy := SDL.SDL_RenderClear (Ren);
      Fill_Rect (0, 0, Win_W, Win_H, (16, 16, 22));

      --  grid
      for I in 0 .. Cols loop
         Fill_Rect (I * Cell, 0, 1, Board_H, (28, 28, 38));
      end loop;
      for I in 0 .. Rows loop
         Fill_Rect (0, I * Cell, Board_W, 1, (28, 28, 38));
      end loop;

      --  locked cells
      for R in 0 .. Rows - 1 loop
         for C in 0 .. Cols - 1 loop
            if G.Board (R) (C) /= None then
               Draw_Cell (C, R, Piece_Defs (G.Board (R) (C)).Color);
            end if;
         end loop;
      end loop;
      Frame_Rect (0, 0, Board_W, Board_H, (90, 90, 110));

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
                        Frame_Rect
                          (BX * Cell + 1, BY * Cell + 1, Cell - 2, Cell - 2,
                           Piece_Defs (G.Current).Color);
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
                  Draw_Cell (BX, BY, Piece_Defs (G.Current).Color);
               end if;
            end;
         end loop;
      end if;

      --  side panel
      Draw_Text (Font_Small, Panel_X, 16, "SCORE", Dim);
      Draw_Text (Font_Med, Panel_X, 36, St.Score'Img, White);
      Draw_Text (Font_Small, Panel_X, 92, "LINES", Dim);
      Draw_Text (Font_Med, Panel_X, 112, St.Lines'Img, White);
      Draw_Text (Font_Small, Panel_X, 168, "LEVEL", Dim);
      Draw_Text (Font_Med, Panel_X, 188, St.Level'Img, White);

      Draw_Text (Font_Small, Panel_X, 244, "NEXT", Dim);
      Fill_Rect (Panel_X - 6, 264, 4 * Pc + 12, 4 * Pc + 12, (24, 24, 32));
      Frame_Rect (Panel_X - 6, 264, 4 * Pc + 12, 4 * Pc + 12, (70, 70, 90));
      Draw_Preview (Peek_Next (G), Panel_X, 270, Pc);

      Draw_Text (Font_Small, Panel_X, 368, "HOLD", Dim);
      Fill_Rect (Panel_X - 6, 388, 4 * Pc + 12, 4 * Pc + 12, (24, 24, 32));
      Frame_Rect (Panel_X - 6, 388, 4 * Pc + 12, 4 * Pc + 12, (70, 70, 90));
      Draw_Preview (G.Hold, Panel_X, 394, Pc);

      Draw_Text (Font_Small, Panel_X, 500, "Arrows move/drop", Dim);
      Draw_Text (Font_Small, Panel_X, 520, "Up/X rot, Z ccw", Dim);
      Draw_Text (Font_Small, Panel_X, 540, "Space hard drop", Dim);
      Draw_Text (Font_Small, Panel_X, 560, "C hold, P pause", Dim);
      Draw_Text (Font_Small, Panel_X, 580, "R restart, Esc quit", Dim);

      --  overlays
      if G.Over or else G.Paused then
         Fill_Rect (0, 0, Board_W, Board_H, (0, 0, 0), 170);
         if G.Over then
            Draw_Text (Font_Big, 60, Board_H / 2 - 60, "GAME OVER", (255, 80, 80));
            Draw_Text (Font_Med, 82, Board_H / 2 - 10, "Score" & G.Score'Img, White);
            Draw_Text (Font_Small, 79, Board_H / 2 + 34, "Press R to restart", Dim);
         else
            Draw_Text (Font_Big, 95, Board_H / 2 - 20, "PAUSED", White);
         end if;
      end if;

      SDL.SDL_RenderPresent (Ren);
   end Render;

   --  headless screenshot ----------------------------------------------------
   procedure Dump_PPM (Path : String) is
      use Ada.Streams.Stream_IO;
      type Byte_Array is array (Natural range <>) of SDL.Uint8;
      type Byte_Array_Ptr is access Byte_Array;
      N   : constant Natural := Win_W * Win_H * 4;
      Buf : constant Byte_Array_Ptr := new Byte_Array (0 .. N - 1);
      Res : Interfaces.C.int;
      File : File_Type;
      Header : constant String :=
        "P6" & Ada.Characters.Latin_1.LF
        & Win_W'Img & " " & Win_H'Img & Ada.Characters.Latin_1.LF
        & "255" & Ada.Characters.Latin_1.LF;
   begin
      Res := SDL.SDL_RenderReadPixels
        (Ren, null, SDL.SDL_PIXELFORMAT_ARGB8888, Buf.all'Address,
         Interfaces.C.int (Win_W * 4));
      if Res /= 0 then
         Ada.Text_IO.Put_Line
           ("RenderReadPixels failed: " & To_Ada (SDL.SDL_GetError));
         return;
      end if;
      Create (File, Out_File, Path);
      String'Write (Stream (File), Header);
      for I in 0 .. Win_W * Win_H - 1 loop
         --  ARGB8888 in memory (little-endian) is B,G,R,A
         SDL.Uint8'Write (Stream (File), Buf (I * 4 + 2));  --  R
         SDL.Uint8'Write (Stream (File), Buf (I * 4 + 1));  --  G
         SDL.Uint8'Write (Stream (File), Buf (I * 4 + 0));  --  B
      end loop;
      Close (File);
   end Dump_PPM;

   --  font discovery ----------------------------------------------------------
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
               F : constant SDL.TTF_Font_Ptr :=
                 SDL.TTF_OpenFont (To_C (To_String (C)), 22);
            begin
               if F /= null then
                  SDL.TTF_CloseFont (F);
                  return C;
               end if;
            end;
         end if;
      end loop;
      return To_Unbounded_String ("");
   end Find_Font;

   --  main --------------------------------------------------------------------
   Demo_Frames : Natural := 0;
   Demo_Seed   : SDL.Uint32 := 12345;
   Seed        : Integer := 0;
   Win         : SDL.SDL_Window_Ptr;
   Running     : Boolean := True;
   Frame       : Natural := 0;
   Now, Last   : SDL.Uint32;
   Dt          : SDL.Uint32;
   Ev          : aliased SDL.SDL_Event;
   Font_Path   : Ada.Strings.Unbounded.Unbounded_String;

begin
   --  env hooks
   if Ada.Environment_Variables.Exists ("TETRIS_DEMO") then
      Demo_Frames := Natural'Value (Ada.Environment_Variables.Value ("TETRIS_DEMO"));
   end if;
   if Ada.Environment_Variables.Exists ("TETRIS_PRELOAD") then
      Preload := True;
   end if;
   if Ada.Environment_Variables.Exists ("TETRIS_SEED") then
      Seed := Integer'Value (Ada.Environment_Variables.Value ("TETRIS_SEED"));
   else
      declare
         T : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      begin
         Seed := Ada.Calendar.Year (T) * 10000 + Ada.Calendar.Day (T) * 100
           + Integer (Ada.Calendar.Seconds (T));
      end;
   end if;

   if SDL.SDL_Init (SDL.SDL_INIT_VIDEO) /= 0 then
      Ada.Text_IO.Put_Line ("SDL_Init failed: " & To_Ada (SDL.SDL_GetError));
      return;
   end if;
   if SDL.TTF_Init /= 0 then
      Ada.Text_IO.Put_Line ("TTF_Init failed: " & To_Ada (SDL.SDL_GetError)
                            & " (continuing without text)");
   end if;

   Font_Path := Find_Font;

   Win := SDL.SDL_CreateWindow
     (To_C ("Ada Tetris - SDL2"), SDL.SDL_WINDOWPOS_CENTERED,
      SDL.SDL_WINDOWPOS_CENTERED, Interfaces.C.int (Win_W),
      Interfaces.C.int (Win_H), SDL.SDL_WINDOW_SHOWN);
   if Win = null then
      Ada.Text_IO.Put_Line ("SDL_CreateWindow failed: " & To_Ada (SDL.SDL_GetError));
      return;
   end if;

   Ren := SDL.SDL_CreateRenderer
     (Win, -1, SDL.SDL_RENDERER_ACCELERATED or SDL.SDL_RENDERER_PRESENTVSYNC);
   if Ren = null then
      Ren := SDL.SDL_CreateRenderer (Win, -1, SDL.SDL_RENDERER_SOFTWARE);
   end if;
   if Ren = null then
      Ada.Text_IO.Put_Line ("SDL_CreateRenderer failed: "
                            & To_Ada (SDL.SDL_GetError));
      return;
   end if;
   declare
      Dummy : constant Interfaces.C.int :=
        SDL.SDL_SetRenderDrawBlendMode (Ren, SDL.SDL_BLENDMODE_BLEND);
   begin
      null;
   end;

   if Ada.Strings.Unbounded.Length (Font_Path) > 0 then
      declare
         P : constant String := Ada.Strings.Unbounded.To_String (Font_Path);
      begin
         Font_Small := SDL.TTF_OpenFont (To_C (P), 15);
         Font_Med   := SDL.TTF_OpenFont (To_C (P), 22);
         Font_Big   := SDL.TTF_OpenFont (To_C (P), 36);
      end;
   end if;

   Seven_Rand.Reset (Gen, Seed);
   New_Game (St);

   Last := SDL.SDL_GetTicks;
   while Running loop
      Now := SDL.SDL_GetTicks;
      Dt := Now - Last;
      Last := Now;

      while SDL.SDL_PollEvent (Ev'Access) = 1 loop
         case Ev.EType is
            when SDL.EV_QUIT =>
               Running := False;
            when SDL.EV_KEYDOWN =>
               if Ev.Repeat = 0 then
                  case Ev.Keysym.Sym is
                     when SDL.SDLK_ESCAPE =>
                        Running := False;
                     when SDL.SDLK_LEFT =>
                        if Playing and then not Left_Held then
                           Do_Action (Move_L);
                           Dir := -1;
                           Move_Start := Now;
                           Last_Arr := Now;
                        end if;
                        Left_Held := True;
                     when SDL.SDLK_RIGHT =>
                        if Playing and then not Right_Held then
                           Do_Action (Move_R);
                           Dir := 1;
                           Move_Start := Now;
                           Last_Arr := Now;
                        end if;
                        Right_Held := True;
                     when SDL.SDLK_DOWN =>
                        Down_Held := True;
                     when SDL.SDLK_UP | SDL.SDLK_x =>
                        Do_Action (Rot_CW);
                     when SDL.SDLK_z =>
                        Do_Action (Rot_CCW);
                     when SDL.SDLK_SPACE =>
                        Do_Action (Hard);
                     when SDL.SDLK_c =>
                        Do_Action (Hold_A);
                     when SDL.SDLK_p =>
                        if not St.Over then
                           St.Paused := not St.Paused;
                        end if;
                     when SDL.SDLK_r =>
                        New_Game (St);
                     when others =>
                        null;
                  end case;
               else
                  case Ev.Keysym.Sym is
                     when SDL.SDLK_LEFT  => Left_Held := True;
                     when SDL.SDLK_RIGHT => Right_Held := True;
                     when SDL.SDLK_DOWN  => Down_Held := True;
                     when others         => null;
                  end case;
               end if;
            when SDL.EV_KEYUP =>
               case Ev.Keysym.Sym is
                  when SDL.SDLK_LEFT =>
                     Left_Held := False;
                     if Right_Held then
                        Dir := 1;
                        Move_Start := Now;
                        Last_Arr := Now;
                     else
                        Dir := 0;
                     end if;
                  when SDL.SDLK_RIGHT =>
                     Right_Held := False;
                     if Left_Held then
                        Dir := -1;
                        Move_Start := Now;
                        Last_Arr := Now;
                     else
                        Dir := 0;
                     end if;
                  when SDL.SDLK_DOWN =>
                     Down_Held := False;
                  when others =>
                     null;
               end case;
            when others =>
               null;
         end case;
      end loop;

      --  scripted input for headless demo mode
      if Demo_Frames > 0 then
         if Preload then
            case Frame is
               when 5              => Do_Action (Rot_CW);
               when 10 | 11 | 12 | 13 => Do_Action (Move_R);
               when 20             => Do_Action (Hard);
               when others         => null;
            end case;
         else
            Demo_Seed := Demo_Seed * SDL.Uint32 (1103515245) + SDL.Uint32 (12345);
            case Natural ((Demo_Seed / SDL.Uint32 (65536)) mod SDL.Uint32 (10)) is
               when 0 | 1  => Do_Action (Move_L);
               when 2 | 3  => Do_Action (Move_R);
               when 4      => Do_Action (Rot_CW);
               when 5      => Do_Action (Rot_CCW);
               when 6      => Do_Action (Hold_A);
               when 7 .. 9 => Do_Action (Hard);
               when others => null;
            end case;
         end if;
      end if;

      if Playing then
         --  DAS auto-repeat for left/right
         if Dir /= 0 and then Now - Move_Start >= Das_Delay
           and then Now - Last_Arr >= Arr_Delay
         then
            Do_Action (if Dir < 0 then Move_L else Move_R);
            Last_Arr := Now;
         end if;

         --  gravity
         declare
            Interval : constant SDL.Uint32 :=
              (if Down_Held then SDL.Uint32 (30) else Drop_Interval (St.Level));
         begin
            St.Drop_Acc := St.Drop_Acc + Dt;
            while St.Drop_Acc >= Interval and then Playing loop
               St.Drop_Acc := St.Drop_Acc - Interval;
               if Down_Held then
                  St.Score := St.Score + 1;   --  soft drop
               end if;
               Step_Down (St);
            end loop;
         end;
      end if;

      Render (St);
      Frame := Frame + 1;

      if Demo_Frames > 0 then
         SDL.SDL_Delay (16);   --  ~60 fps even without vsync (dummy driver)
         if Frame >= Demo_Frames then
            Dump_PPM ("tetris_demo.ppm");
            Ada.Text_IO.Put_Line
              ("DEMO DONE frames=" & Frame'Img
               & " score=" & St.Score'Img
               & " lines=" & St.Lines'Img
               & " level=" & St.Level'Img
               & (if St.Over then " GAME_OVER" else ""));
            Running := False;
         end if;
      end if;
   end loop;

   if Font_Small /= null then SDL.TTF_CloseFont (Font_Small); end if;
   if Font_Med /= null then SDL.TTF_CloseFont (Font_Med); end if;
   if Font_Big /= null then SDL.TTF_CloseFont (Font_Big); end if;
   SDL.TTF_Quit;
   SDL.SDL_DestroyRenderer (Ren);
   SDL.SDL_DestroyWindow (Win);
   SDL.SDL_Quit;
end Tetris;
