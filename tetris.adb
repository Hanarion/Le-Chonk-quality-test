--  Ada/SDL2 Tetris. All logic lives in packages; this main just runs the game.
--
--  Controls: Left/Right move (DAS auto-repeat), Down soft drop, Up or X
--  rotate CW, Z rotate CCW, Space hard drop, C hold, P pause, R restart,
--  Esc quit.
with Tetris_Game;

procedure Tetris is
begin
   Tetris_Game.Run;
end Tetris;
