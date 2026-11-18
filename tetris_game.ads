--  Controller: owns the SDL window/renderer, the event loop, input mapping
--  (incl. DAS auto-repeat), gravity timing, and the headless demo hooks.
--
--  Demo/test env vars:
--    TETRIS_DEMO=N     run N frames with scripted input, dump
--                      tetris_demo.ppm, print final score/lines, exit
--    TETRIS_SEED=S     fixed RNG seed (default: from the clock)
--    TETRIS_PRELOAD=1  load the model's line-clear test scenario
--    TETRIS_FONT=path  override the font file
package Tetris_Game is

   procedure Run;

end Tetris_Game;
