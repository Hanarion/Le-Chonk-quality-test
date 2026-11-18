--  Minimal SDL2 Ada bindings: init, window, renderer, events, timing,
--  surfaces/textures. Pure declarations + pragma Import (no C headers).
with Interfaces.C;
with System;

package SDL is

   subtype Uint8  is Interfaces.C.unsigned_char;
   subtype Uint16 is Interfaces.C.unsigned_short;
   subtype Uint32 is Interfaces.C.unsigned;

   --  init ---------------------------------------------------------------
   SDL_INIT_VIDEO : constant Uint32 := 16#0000_0020#;

   function SDL_Init (Flags : Uint32) return Interfaces.C.int;
   pragma Import (C, SDL_Init, "SDL_Init");

   procedure SDL_Quit;
   pragma Import (C, SDL_Quit, "SDL_Quit");

   function SDL_GetError return Interfaces.C.char_array;
   pragma Import (C, SDL_GetError, "SDL_GetError");

   --  window / renderer ----------------------------------------------------
   type SDL_Window is null record;
   pragma Convention (C, SDL_Window);
   type SDL_Window_Ptr is access all SDL_Window;

   type SDL_Renderer is null record;
   pragma Convention (C, SDL_Renderer);
   type SDL_Renderer_Ptr is access all SDL_Renderer;

   SDL_WINDOW_SHOWN          : constant Uint32 := 16#0000_0004#;
   SDL_WINDOWPOS_CENTERED    : constant Interfaces.C.int := 16#2FFF_0000#;
   SDL_RENDERER_SOFTWARE     : constant Uint32 := 16#0000_0001#;
   SDL_RENDERER_ACCELERATED  : constant Uint32 := 16#0000_0002#;
   SDL_RENDERER_PRESENTVSYNC : constant Uint32 := 16#0000_0004#;
   SDL_BLENDMODE_BLEND       : constant Uint32 := 16#0000_0001#;

   function SDL_CreateWindow
     (Title : Interfaces.C.char_array;
      X, Y, W, H : Interfaces.C.int;
      Flags : Uint32) return SDL_Window_Ptr;
   pragma Import (C, SDL_CreateWindow, "SDL_CreateWindow");

   procedure SDL_DestroyWindow (Win : SDL_Window_Ptr);
   pragma Import (C, SDL_DestroyWindow, "SDL_DestroyWindow");

   function SDL_CreateRenderer
     (Win : SDL_Window_Ptr; Index : Interfaces.C.int; Flags : Uint32)
      return SDL_Renderer_Ptr;
   pragma Import (C, SDL_CreateRenderer, "SDL_CreateRenderer");

   procedure SDL_DestroyRenderer (Ren : SDL_Renderer_Ptr);
   pragma Import (C, SDL_DestroyRenderer, "SDL_DestroyRenderer");

   type SDL_Rect is record
      X, Y, W, H : Interfaces.C.int;
   end record;
   pragma Convention (C, SDL_Rect);
   for SDL_Rect'Size use 128;

   function SDL_SetRenderDrawColor
     (Ren : SDL_Renderer_Ptr; R, G, B, A : Uint8) return Interfaces.C.int;
   pragma Import (C, SDL_SetRenderDrawColor, "SDL_SetRenderDrawColor");

   function SDL_SetRenderDrawBlendMode
     (Ren : SDL_Renderer_Ptr; Mode : Uint32) return Interfaces.C.int;
   pragma Import (C, SDL_SetRenderDrawBlendMode, "SDL_SetRenderDrawBlendMode");

   function SDL_RenderClear (Ren : SDL_Renderer_Ptr) return Interfaces.C.int;
   pragma Import (C, SDL_RenderClear, "SDL_RenderClear");

   function SDL_RenderFillRect
     (Ren : SDL_Renderer_Ptr; Rect : access SDL_Rect) return Interfaces.C.int;
   pragma Import (C, SDL_RenderFillRect, "SDL_RenderFillRect");

   function SDL_RenderDrawRect
     (Ren : SDL_Renderer_Ptr; Rect : access SDL_Rect) return Interfaces.C.int;
   pragma Import (C, SDL_RenderDrawRect, "SDL_RenderDrawRect");

   procedure SDL_RenderPresent (Ren : SDL_Renderer_Ptr);
   pragma Import (C, SDL_RenderPresent, "SDL_RenderPresent");

   SDL_PIXELFORMAT_ARGB8888 : constant Uint32 := 16#1636_2004#;

   function SDL_RenderReadPixels
     (Ren : SDL_Renderer_Ptr; Rect : access SDL_Rect; Format : Uint32;
      Pixels : System.Address; Pitch : Interfaces.C.int) return Interfaces.C.int;
   pragma Import (C, SDL_RenderReadPixels, "SDL_RenderReadPixels");

   --  events / timing -------------------------------------------------------
   EV_QUIT    : constant Uint32 := 16#0000_0100#;
   EV_KEYDOWN : constant Uint32 := 16#0000_0300#;
   EV_KEYUP   : constant Uint32 := 16#0000_0301#;

   --  keycodes (SDLK_* = scancode | 1<<30 for the non-ASCII keys)
   SDLK_ESCAPE : constant Interfaces.C.int := 27;
   SDLK_SPACE  : constant Interfaces.C.int := 32;
   SDLK_c      : constant Interfaces.C.int := 99;
   SDLK_p      : constant Interfaces.C.int := 112;
   SDLK_r      : constant Interfaces.C.int := 114;
   SDLK_x      : constant Interfaces.C.int := 120;
   SDLK_z      : constant Interfaces.C.int := 122;
   SDLK_RIGHT  : constant Interfaces.C.int := 16#4000_004F#;
   SDLK_LEFT   : constant Interfaces.C.int := 16#4000_0050#;
   SDLK_DOWN   : constant Interfaces.C.int := 16#4000_0051#;
   SDLK_UP     : constant Interfaces.C.int := 16#4000_0052#;

   type SDL_Keysym is record
      Scancode  : Interfaces.C.int;
      Sym       : Interfaces.C.int;
      Modifiers : Uint16;
      Unused    : Uint32;
   end record;
   pragma Convention (C, SDL_Keysym);
   for SDL_Keysym'Size use 128;

   type Uint32_Array_24 is array (1 .. 24) of Uint32;

   --  128-byte SDL_Event union; the keyboard-event fields sit at their
   --  C offsets so Ev.Keysym is directly readable for KEYDOWN/KEYUP.
   type SDL_Event is record
      EType     : Uint32;
      Timestamp : Uint32;
      WindowID  : Uint32;
      State     : Uint8;
      Repeat    : Uint8;
      Pad2      : Uint8;
      Pad3      : Uint8;
      Keysym    : SDL_Keysym;
      Tail      : Uint32_Array_24;
   end record;
   pragma Convention (C, SDL_Event);
   for SDL_Event'Size use 1024;

   function SDL_PollEvent (Event : access SDL_Event) return Interfaces.C.int;
   pragma Import (C, SDL_PollEvent, "SDL_PollEvent");

   procedure SDL_Delay (Ms : Uint32);
   pragma Import (C, SDL_Delay, "SDL_Delay");

   function SDL_GetTicks return Uint32;
   pragma Import (C, SDL_GetTicks, "SDL_GetTicks");

   --  surfaces / textures --------------------------------------------------
   type SDL_Surface is null record;
   pragma Convention (C, SDL_Surface);
   type SDL_Surface_Ptr is access all SDL_Surface;

   type SDL_Texture is null record;
   pragma Convention (C, SDL_Texture);
   type SDL_Texture_Ptr is access all SDL_Texture;

   type SDL_Color is record
      R, G, B, A : Uint8;
   end record;
   pragma Convention (C, SDL_Color);

   function SDL_CreateTextureFromSurface
     (Ren : SDL_Renderer_Ptr; Surf : SDL_Surface_Ptr) return SDL_Texture_Ptr;
   pragma Import (C, SDL_CreateTextureFromSurface, "SDL_CreateTextureFromSurface");

   procedure SDL_DestroyTexture (Tex : SDL_Texture_Ptr);
   pragma Import (C, SDL_DestroyTexture, "SDL_DestroyTexture");

   procedure SDL_FreeSurface (Surf : SDL_Surface_Ptr);
   pragma Import (C, SDL_FreeSurface, "SDL_FreeSurface");

   function SDL_QueryTexture
     (Tex : SDL_Texture_Ptr; Format : access Uint32; Acc : access Interfaces.C.int;
      W, H : access Interfaces.C.int) return Interfaces.C.int;
   pragma Import (C, SDL_QueryTexture, "SDL_QueryTexture");

   function SDL_RenderCopy
     (Ren : SDL_Renderer_Ptr; Tex : SDL_Texture_Ptr;
      Src, Dst : access SDL_Rect) return Interfaces.C.int;
   pragma Import (C, SDL_RenderCopy, "SDL_RenderCopy");

end SDL;
