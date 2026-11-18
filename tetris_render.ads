--  Presentation layer: window geometry, colors, text, board drawing,
--  headless PPM screenshot. Depends on SDL/SDL_TTF and the model, nothing else.
with Ada.Strings.Unbounded;
with SDL;
with SDL_TTF;
with Tetris_Model;

package Tetris_Render is

   Cell_Size   : constant := 32;   --  board cell, px
   Panel_Width : constant := 220;

   Board_Pixel_Width  : constant := Tetris_Model.Cols * Cell_Size;
   Board_Pixel_Height : constant := Tetris_Model.Rows * Cell_Size;
   Window_Width       : constant := Board_Pixel_Width + Panel_Width;
   Window_Height      : constant := Board_Pixel_Height;

   type Font_Set is record
      Small, Med, Big : SDL_TTF.TTF_Font_Ptr;
   end record;

   --  First usable font file: $TETRIS_FONT, then common system fonts.
   function Find_Font return Ada.Strings.Unbounded.Unbounded_String;

   procedure Open_Fonts (Path : String; Fonts : out Font_Set);
   procedure Close_Fonts (Fonts : in out Font_Set);

   procedure Draw
     (Ren : SDL.SDL_Renderer_Ptr; Fonts : Font_Set; G : Tetris_Model.Game_State);

   --  Read back the framebuffer and write it as a binary PPM (test hook).
   procedure Dump_PPM (Ren : SDL.SDL_Renderer_Ptr; Path : String);

end Tetris_Render;
