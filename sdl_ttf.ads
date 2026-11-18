--  Minimal SDL2_ttf Ada bindings (text rendering).
with Interfaces.C;
with SDL;

package SDL_TTF is

   type TTF_Font is null record;
   pragma Convention (C, TTF_Font);
   type TTF_Font_Ptr is access all TTF_Font;

   function TTF_Init return Interfaces.C.int;
   pragma Import (C, TTF_Init, "TTF_Init");

   procedure TTF_Quit;
   pragma Import (C, TTF_Quit, "TTF_Quit");

   function TTF_OpenFont
     (File : Interfaces.C.char_array; PtSize : Interfaces.C.int) return TTF_Font_Ptr;
   pragma Import (C, TTF_OpenFont, "TTF_OpenFont");

   procedure TTF_CloseFont (Font : TTF_Font_Ptr);
   pragma Import (C, TTF_CloseFont, "TTF_CloseFont");

   function TTF_RenderUTF8_Solid
     (Font : TTF_Font_Ptr; Text : Interfaces.C.char_array; Fg : SDL.SDL_Color)
      return SDL.SDL_Surface_Ptr;
   pragma Import (C, TTF_RenderUTF8_Solid, "TTF_RenderUTF8_Solid");

end SDL_TTF;
