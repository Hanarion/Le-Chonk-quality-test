--  Tetris_Game body: SDL setup + main loop.
with Ada.Calendar;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces.C;
with SDL;
with SDL_TTF;
with Tetris_Model;
with Tetris_Render;

package body Tetris_Game is

   use Interfaces.C;
   use type SDL.Uint32;
   use type SDL.SDL_Window_Ptr;
   use type SDL.SDL_Renderer_Ptr;

   Das_Delay : constant SDL.Uint32 := 150;   --  ms before auto-repeat starts
   Arr_Delay : constant SDL.Uint32 := 40;    --  ms between auto-repeats

   procedure Run is
      use Tetris_Model;

      Demo_Frames : Natural := 0;
      Demo_Seed   : SDL.Uint32 := 12345;
      Seed        : Integer := 0;
      Preload     : Boolean := False;
      Win         : SDL.SDL_Window_Ptr;
      Ren         : SDL.SDL_Renderer_Ptr;
      Fonts       : Tetris_Render.Font_Set;
      Font_Path   : Ada.Strings.Unbounded.Unbounded_String;
      St          : Game_State;
      Left_Held   : Boolean := False;
      Right_Held  : Boolean := False;
      Down_Held   : Boolean := False;
      Dir         : Integer := 0;               --  DAS direction: -1, 0, +1
      Move_Start  : SDL.Uint32 := 0;
      Last_Arr    : SDL.Uint32 := 0;
      Now, Last   : SDL.Uint32;
      Dt          : SDL.Uint32;
      Ev          : aliased SDL.SDL_Event;
      Running     : Boolean := True;
      Frame       : Natural := 0;
      Dummy       : Interfaces.C.int;
      pragma Unreferenced (Dummy);
   begin
      --  env hooks
      if Ada.Environment_Variables.Exists ("TETRIS_DEMO") then
         Demo_Frames :=
           Natural'Value (Ada.Environment_Variables.Value ("TETRIS_DEMO"));
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
      if SDL_TTF.TTF_Init /= 0 then
         Ada.Text_IO.Put_Line ("TTF_Init failed: " & To_Ada (SDL.SDL_GetError)
                               & " (continuing without text)");
      end if;

      Font_Path := Tetris_Render.Find_Font;

      Win := SDL.SDL_CreateWindow
        (To_C ("Ada Tetris - SDL2"), SDL.SDL_WINDOWPOS_CENTERED,
         SDL.SDL_WINDOWPOS_CENTERED, Interfaces.C.int (Tetris_Render.Window_Width),
         Interfaces.C.int (Tetris_Render.Window_Height), SDL.SDL_WINDOW_SHOWN);
      if Win = null then
         Ada.Text_IO.Put_Line ("SDL_CreateWindow failed: "
                               & To_Ada (SDL.SDL_GetError));
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
      Dummy := SDL.SDL_SetRenderDrawBlendMode (Ren, SDL.SDL_BLENDMODE_BLEND);

      if Ada.Strings.Unbounded.Length (Font_Path) > 0 then
         Tetris_Render.Open_Fonts
           (Ada.Strings.Unbounded.To_String (Font_Path), Fonts);
      end if;

      Seed_Game : declare
      begin
         Tetris_Model.Seed (Seed);
      end Seed_Game;
      New_Game (St);
      if Preload then
         Load_Test_Scenario (St);
      end if;

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
                           if Playing (St) and then not Left_Held then
                              Do_Action (St, Move_L);
                              Dir := -1;
                              Move_Start := Now;
                              Last_Arr := Now;
                           end if;
                           Left_Held := True;
                        when SDL.SDLK_RIGHT =>
                           if Playing (St) and then not Right_Held then
                              Do_Action (St, Move_R);
                              Dir := 1;
                              Move_Start := Now;
                              Last_Arr := Now;
                           end if;
                           Right_Held := True;
                        when SDL.SDLK_DOWN =>
                           Down_Held := True;
                        when SDL.SDLK_UP | SDL.SDLK_x =>
                           Do_Action (St, Rot_CW);
                        when SDL.SDLK_z =>
                           Do_Action (St, Rot_CCW);
                        when SDL.SDLK_SPACE =>
                           Do_Action (St, Hard);
                        when SDL.SDLK_c =>
                           Do_Action (St, Hold_A);
                        when SDL.SDLK_p =>
                           if not St.Over then
                              St.Paused := not St.Paused;
                           end if;
                        when SDL.SDLK_r =>
                           New_Game (St);
                           Left_Held := False;
                           Right_Held := False;
                           Down_Held := False;
                           Dir := 0;
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
                  when 5                 => Do_Action (St, Rot_CW);
                  when 10 | 11 | 12 | 13 => Do_Action (St, Move_R);
                  when 20                => Do_Action (St, Hard);
                  when others            => null;
               end case;
            else
               Demo_Seed := Demo_Seed * SDL.Uint32 (1103515245) + SDL.Uint32 (12345);
               case Natural ((Demo_Seed / SDL.Uint32 (65536)) mod SDL.Uint32 (10)) is
                  when 0 | 1  => Do_Action (St, Move_L);
                  when 2 | 3  => Do_Action (St, Move_R);
                  when 4      => Do_Action (St, Rot_CW);
                  when 5      => Do_Action (St, Rot_CCW);
                  when 6      => Do_Action (St, Hold_A);
                  when 7 .. 9 => Do_Action (St, Hard);
                  when others => null;
               end case;
            end if;
         end if;

         if Playing (St) then
            --  DAS auto-repeat for left/right
            if Dir /= 0 and then Now - Move_Start >= Das_Delay
              and then Now - Last_Arr >= Arr_Delay
            then
               Do_Action (St, (if Dir < 0 then Move_L else Move_R));
               Last_Arr := Now;
            end if;

            --  gravity
            declare
               Interval : constant Natural :=
                 (if Down_Held then 30 else Drop_Interval (St.Level));
            begin
               St.Drop_Acc := St.Drop_Acc + Natural (Dt);
               while St.Drop_Acc >= Interval and then Playing (St) loop
                  St.Drop_Acc := St.Drop_Acc - Interval;
                  if Down_Held then
                     St.Score := St.Score + 1;   --  soft drop
                  end if;
                  Step_Down (St);
               end loop;
            end;
         end if;

         Tetris_Render.Draw (Ren, Fonts, St);
         Frame := Frame + 1;

         if Demo_Frames > 0 then
            SDL.SDL_Delay (16);   --  ~60 fps even without vsync (dummy driver)
            if Frame >= Demo_Frames then
               Tetris_Render.Dump_PPM (Ren, "tetris_demo.ppm");
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

      Tetris_Render.Close_Fonts (Fonts);
      SDL_TTF.TTF_Quit;
      SDL.SDL_DestroyRenderer (Ren);
      SDL.SDL_DestroyWindow (Win);
      SDL.SDL_Quit;
   end Run;

end Tetris_Game;
