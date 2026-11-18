--  Tetris_Model body: rules only, no I/O.
with Ada.Numerics.Discrete_Random;

package body Tetris_Model is

   package Seven_Rand is new Ada.Numerics.Discrete_Random (Seven);

   Gen : Seven_Rand.Generator;

   Piece_Defs : constant array (Piece_Kind) of Piece_Def :=
     (None => (2, ((0, 0), (0, 0), (0, 0), (0, 0)), (0, 0, 0)),
      I_P  => (4, ((0, 1), (1, 1), (2, 1), (3, 1)), (0, 240, 240)),
      O_P  => (2, ((0, 0), (1, 0), (0, 1), (1, 1)), (240, 240, 0)),
      T_P  => (3, ((1, 0), (0, 1), (1, 1), (2, 1)), (170, 0, 240)),
      S_P  => (3, ((1, 0), (2, 0), (0, 1), (1, 1)), (0, 230, 0)),
      Z_P  => (3, ((0, 0), (1, 0), (1, 1), (2, 1)), (240, 0, 0)),
      J_P  => (3, ((0, 0), (0, 1), (1, 1), (2, 1)), (0, 0, 240)),
      L_P  => (3, ((2, 0), (0, 1), (1, 1), (2, 1)), (240, 160, 0)));

   Kicks : constant array (1 .. 6) of Coord :=
     ((0, 0), (-1, 0), (1, 0), (0, -1), (-2, 0), (2, 0));

   function Def (K : Piece_Kind) return Piece_Def is (Piece_Defs (K));

   procedure Seed (S : Integer) is
   begin
      Seven_Rand.Reset (Gen, S);
   end Seed;

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

   function Playing (G : Game_State) return Boolean is
     (not G.Over and then not G.Paused);

   procedure Do_Action (G : in out Game_State; A : Action) is
   begin
      if not Playing (G) then
         return;
      end if;
      case A is
         when Move_L  => if Try_Move (G, -1, 0) then null; end if;
         when Move_R  => if Try_Move (G, 1, 0) then null; end if;
         when Rot_CW  => if Try_Rotate (G, 1) then null; end if;
         when Rot_CCW => if Try_Rotate (G, 3) then null; end if;
         when Hard    => Hard_Drop (G);
         when Hold_A  => Hold_Piece (G);
      end case;
   end Do_Action;

   function Drop_Interval (Level : Natural) return Natural is
      F : constant Float := 1000.0 * 0.85 ** (Level - 1);
   begin
      if F < 50.0 then
         return 50;
      end if;
      return Natural (Integer (F));
   end Drop_Interval;

   procedure New_Game (G : out Game_State) is
   begin
      G := (others => <>);
      Refill_Bag (G);
      Spawn (G);
   end New_Game;

   procedure Load_Test_Scenario (G : in out Game_State) is
   begin
      for C in 0 .. Cols - 2 loop
         G.Board (Rows - 1) (C) := Z_P;
      end loop;
      G.Bag := (I_P, O_P, T_P, S_P, Z_P, J_P, L_P);
      G.Bag_Idx := 1;
      Spawn (G);
   end Load_Test_Scenario;

end Tetris_Model;
