--  Pure Tetris game logic: board, pieces, rotation, line clears, scoring.
--  No SDL dependency, so this package is unit-testable headless.
package Tetris_Model is

   Cols : constant := 10;
   Rows : constant := 20;

   type RGB is record
      R, G, B : Natural range 0 .. 255;
   end record;

   type Piece_Kind is (None, I_P, O_P, T_P, S_P, Z_P, J_P, L_P);
   subtype Real_Kind is Piece_Kind range I_P .. L_P;

   type Coord is record
      X, Y : Integer;
   end record;

   type Cells is array (1 .. 4) of Coord;

   type Piece_Def is record
      Size  : Integer;   --  bounding box: 2, 3 or 4
      Base  : Cells;     --  cells in rotation state 0
      Color : RGB;
   end record;

   function Def (K : Piece_Kind) return Piece_Def;

   type Row_Type   is array (0 .. Cols - 1) of Piece_Kind;
   type Board_Type is array (0 .. Rows - 1) of Row_Type;

   subtype Seven is Integer range 1 .. 7;
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
      Drop_Acc  : Natural := 0;   --  ms accumulated toward the next gravity step
      Over      : Boolean := False;
      Paused    : Boolean := False;
   end record;

   type Action is (Move_L, Move_R, Rot_CW, Rot_CCW, Hard, Hold_A);

   procedure Seed (S : Integer);
   procedure New_Game (G : out Game_State);

   --  Test hook: bottom row filled except column 9, next piece forced to I,
   --  so a vertical I dropped in column 9 clears exactly one line.
   procedure Load_Test_Scenario (G : in out Game_State);

   function Playing   (G : Game_State) return Boolean;
   function Peek_Next (G : Game_State) return Real_Kind;
   function Cells_Of  (K : Real_Kind; Rot : Natural) return Cells;
   function Collides  (G : Game_State; K : Real_Kind; Rot : Natural;
                       X, Y : Integer) return Boolean;

   function Try_Move   (G : in out Game_State; DX, DY : Integer) return Boolean;
   function Try_Rotate (G : in out Game_State; Dir : Natural) return Boolean;
   procedure Step_Down (G : in out Game_State);
   procedure Hard_Drop (G : in out Game_State);
   procedure Hold_Piece (G : in out Game_State);
   procedure Do_Action (G : in out Game_State; A : Action);

   --  ms between gravity steps at the given level (>= 1)
   function Drop_Interval (Level : Natural) return Natural;

end Tetris_Model;
