-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                     Copyright (C) 2001-2004                       --
--                            ACT-Europe                             --
--                                                                   --
-- GPS is free  software; you can  redistribute it and/or modify  it --
-- under the terms of the GNU General Public License as published by --
-- the Free Software Foundation; either version 2 of the License, or --
-- (at your option) any later version.                               --
--                                                                   --
-- This program is  distributed in the hope that it will be  useful, --
-- but  WITHOUT ANY WARRANTY;  without even the  implied warranty of --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details. You should have received --
-- a copy of the GNU General Public License along with this library; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with Glib.Values;
with Pango.Font;                use Pango.Font;
with Gdk.Dnd;                   use Gdk.Dnd;
with Glib.Error;                use Glib.Error;
with Glide_Kernel;              use Glide_Kernel;
with Glide_Kernel.Hooks;        use Glide_Kernel.Hooks;
with Glide_Kernel.Modules;      use Glide_Kernel.Modules;
with Glide_Kernel.Actions;      use Glide_Kernel.Actions;
with Glide_Kernel.Preferences;  use Glide_Kernel.Preferences;
with Glide_Kernel.Scripts;      use Glide_Kernel.Scripts;
with Glide_Kernel.Standard_Hooks;
use Glide_Kernel.Standard_Hooks;
with Glib;                      use Glib;
with Gtk.Box;                   use Gtk.Box;
with Gtk.Dnd;                   use Gtk.Dnd;
with Gtk.Enums;                 use Gtk.Enums;
with Gtk.Frame;                 use Gtk.Frame;
with Gtk.Image;                 use Gtk.Image;
with Gtk.Main;                  use Gtk.Main;
with Gtk.Rc;                    use Gtk.Rc;
with Gtk.Window;                use Gtk.Window;
with Gtk.Widget;                use Gtk.Widget;
with Gtk.Dialog;           use Gtk.Dialog;
with Gtk.Label;            use Gtk.Label;
with Gtk.Size_Group;       use Gtk.Size_Group;
with Gtk.GEntry;           use Gtk.GEntry;
with Gtk.Stock;            use Gtk.Stock;
with Gtkada.Dialogs;       use Gtkada.Dialogs;
with Gtkada.Handlers;           use Gtkada.Handlers;
with Gtkada.MDI;                use Gtkada.MDI;
with GNAT.OS_Lib;               use GNAT.OS_Lib;
with Traces;                    use Traces;
with Projects;                  use Projects;
with Glide_Intl;                use Glide_Intl;
with Glide_Kernel.Project;      use Glide_Kernel.Project;
with Glib.Values;               use Glib.Values;
with Commands.Interactive;      use Commands, Commands.Interactive;
with Glib.Generic_Properties;   use Glib.Generic_Properties;
with Glib.Properties.Creation;  use Glib.Properties.Creation;

package body Glide_Main_Window is

   Me : constant Debug_Handle := Create ("Glide_Main_Window");

   Force_Cst      : aliased constant String := "force";
   Msg_Cst        : aliased constant String := "msg";
   Param1_Cst     : aliased constant String := "param1";
   Exit_Cmd_Parameters : constant Cst_Argument_List :=
     (1 => Force_Cst'Access);
   Save_Windows_Parameters : constant Cst_Argument_List :=
     (1 => Force_Cst'Access);
   Dialog_Cmd_Parameters   : constant Cst_Argument_List :=
     (1 => Msg_Cst'Access);
   Input_Dialog_Cmd_Parameters : constant Cst_Argument_List :=
     (1 => Msg_Cst'Access,
      2 => Param1_Cst'Access);

   Vertically_Cst : aliased constant String := "vertically";
   Name_Cst       : aliased constant String := "name";
   Child_Cst      : aliased constant String := "child";
   Side_Cst       : aliased constant String := "side";
   Dock_Cst       : aliased constant String := "dock";
   Iconify_Cst    : aliased constant String := "iconify";
   Float_Cst      : aliased constant String := "float";
   Reuse_Cst      : aliased constant String := "reuse";
   Visible_Only_Cst : aliased constant String := "visible_only";
   Tile_Cmd_Parameters : constant Cst_Argument_List :=
     (1 => Vertically_Cst'Access);
   Get_Cmd_Parameters : constant Cst_Argument_List := (1 => Name_Cst'Access);
   Get_By_Child_Cmd_Parameters : constant Cst_Argument_List :=
     (1 => Child_Cst'Access);
   Dock_Cmd_Parameters : constant Cst_Argument_List :=
     (1 => Dock_Cst'Access, 2 => Side_Cst'Access);
   Iconify_Cmd_Parameters : constant Cst_Argument_List :=
     (1 => Iconify_Cst'Access);
   Float_Cmd_Parameters : constant Cst_Argument_List :=
     (1 => Float_Cst'Access);
   Split_Cmd_Parameters : constant Cst_Argument_List :=
     (1 => Vertically_Cst'Access, 2 => Reuse_Cst'Access);
   Next_Cmd_Parameters : constant Cst_Argument_List :=
     (1 => Visible_Only_Cst'Access);

   type Tabs_Position_Preference is (Bottom, Top, Left, Right);
   for Tabs_Position_Preference'Size use Glib.Gint'Size;
   pragma Convention (C, Tabs_Position_Preference);
   package Tabs_Position_Properties is new Generic_Enumeration_Property
     ("Tabs_Position", Tabs_Position_Preference);

   type Tabs_Policy_Enum is (Never, Automatic, Always);
   for Tabs_Policy_Enum'Size use Glib.Gint'Size;
   pragma Convention (C, Tabs_Policy_Enum);
   package Show_Tabs_Policy_Properties is new Generic_Enumeration_Property
     ("Tabs_Policy", Tabs_Policy_Enum);

   type Toolbar_Icons_Size is (Hide_Toolbar, Small_Icons, Large_Icons);
   for Toolbar_Icons_Size'Size use Glib.Gint'Size;
   pragma Convention (C, Toolbar_Icons_Size);
   package Toolbar_Icons_Size_Properties is new Generic_Enumeration_Property
     ("Toobar_Icons", Toolbar_Icons_Size);

   Pref_Draw_Title_Bars : Param_Spec_Boolean;
   Pref_Tabs_Policy     : Param_Spec_Enum;
   Pref_Tabs_Position   : Param_Spec_Enum;
   Pref_Toolbar_Style   : Param_Spec_Enum;
   Animated_Image_Small : Param_Spec_String;

   function Delete_Callback
     (Widget : access Gtk_Widget_Record'Class;
      Params : Glib.Values.GValues) return Boolean;
   --  Callback for the delete event.

   procedure Preferences_Changed
     (Kernel : access Kernel_Handle_Record'Class);
   --  Called when the preferences have changed.

   procedure On_Destroy (Main_Window : access Gtk_Widget_Record'Class);
   --  Called when the the main window is destroyed

   type Navigation_Mode is (All_Windows, Notebook_Windows);
   type MDI_Child_Selection_Command is new Interactive_Command with record
      Kernel : Kernel_Handle;
      Move_To_Next : Boolean;
      Mode   : Navigation_Mode;
   end record;
   type MDI_Child_Selection_Command_Access is access all
     MDI_Child_Selection_Command'Class;
   function Execute
     (Command : access MDI_Child_Selection_Command;
      Context : Interactive_Command_Context)
      return Command_Return_Type;
   --  Check whether Event should activate the selection dialog for MDI
   --  children.

   type Window_Mode is
     (Split_H, Split_V, Tile_H, Tile_V, Cascade, Maximize, Unmaximize, Single,
      Clone);
   type MDI_Window_Actions_Command is new Interactive_Command with record
      Kernel : Kernel_Handle;
      Mode   : Window_Mode;
   end record;
   type MDI_Window_Actions_Command_Access is access all
     MDI_Window_Actions_Command'Class;
   function Execute
     (Command : access MDI_Window_Actions_Command;
      Context : Interactive_Command_Context)
      return Command_Return_Type;
   --  Act on the layout of windows

   procedure Put_Animation
     (Kernel         : access Kernel_Handle_Record'Class;
      Main_Window    : access Glide_Window_Record'Class;
      File_From_Pref : String);
   --  Add the animated icon to the right of the toolbar

   procedure On_Project_Changed (Kernel : access Kernel_Handle_Record'Class);
   --  Called when the project is changed.

   procedure Default_Command_Handler
     (Data    : in out Callback_Data'Class; Command : String);
   --  Handles shell commands defined in this package

   procedure Default_Window_Command_Handler
     (Data    : in out Callback_Data'Class; Command : String);
   --  Handles shell commands for MDIWindow class

   -------------
   -- Execute --
   -------------

   function Execute
     (Command : access MDI_Window_Actions_Command;
      Context : Interactive_Command_Context)
      return Command_Return_Type
   is
      pragma Unreferenced (Context);
   begin
      case Command.Mode is
         when Split_H =>
            Split (Get_MDI (Command.Kernel), Orientation_Horizontal,
                   After => True);
         when Split_V =>
            Split (Get_MDI (Command.Kernel), Orientation_Vertical,
                   After => True);
         when Tile_H =>
            Tile_Horizontally (Get_MDI (Command.Kernel));
         when Tile_V =>
            Tile_Vertically (Get_MDI (Command.Kernel));
         when Cascade =>
            Cascade_Children (Get_MDI (Command.Kernel));
         when Maximize =>
            Maximize_Children (Get_MDI (Command.Kernel), True);
         when Unmaximize =>
            Maximize_Children (Get_MDI (Command.Kernel), False);
         when Single =>
            Single_Window (Get_MDI (Command.Kernel));
         when Clone =>
            declare
               Focus : constant MDI_Child :=
                 Get_Focus_Child (Get_MDI (Command.Kernel));
               N : MDI_Child;
               pragma Unreferenced (N);
            begin
               if Focus /= null then
                  N  := Dnd_Data (Focus, Copy => True);
               end if;
            end;
      end case;

      return Success;
   end Execute;

   -------------
   -- Anim_Cb --
   -------------

   function Anim_Cb (Kernel : Kernel_Handle) return Boolean is
      Window : constant Glide_Window :=
        Glide_Window (Get_Main_Window (Kernel));
   begin
      if Window.Animation_Image = null then
         return False;

      elsif Advance (Window.Animation_Iter) then
         Set (Window.Animation_Image, Get_Pixbuf (Window.Animation_Iter));
      end if;

      return True;
   end Anim_Cb;

   ---------------------------
   -- Display_Default_Image --
   ---------------------------

   procedure Display_Default_Image (Kernel : Glide_Kernel.Kernel_Handle) is
      Window : constant Glide_Window :=
        Glide_Window (Get_Main_Window (Kernel));
   begin
      if Window.Animation /= null and then Window.Animation_Image /= null then
         Set (Window.Animation_Image, Get_Static_Image (Window.Animation));
      end if;
   end Display_Default_Image;

   -------------
   -- Gtk_New --
   -------------

   procedure Gtk_New
     (Main_Window      : out Glide_Window;
      Key              : String;
      Menu_Items       : Gtk_Item_Factory_Entry_Array;
      Home_Dir         : String;
      Prefix_Directory : String) is
   begin
      Main_Window := new Glide_Window_Record;
      Glide_Main_Window.Initialize
        (Main_Window, Key, Menu_Items, Home_Dir, Prefix_Directory);
   end Gtk_New;

   ----------------------
   -- Confirm_And_Quit --
   ----------------------

   procedure Quit
     (Main_Window : access Glide_Window_Record'Class;
      Force       : Boolean := False) is
   begin
      if Force or else Save_MDI_Children (Main_Window.Kernel) then
         Exit_GPS (Main_Window.Kernel);
      end if;
   end Quit;

   ---------------------
   -- Delete_Callback --
   ---------------------

   function Delete_Callback
     (Widget : access Gtk_Widget_Record'Class;
      Params : Glib.Values.GValues) return Boolean
   is
      pragma Unreferenced (Params);
   begin
      Quit (Glide_Window (Widget));

      return True;
   end Delete_Callback;

   ------------------------
   -- On_Project_Changed --
   ------------------------

   procedure On_Project_Changed
     (Kernel : access Kernel_Handle_Record'Class) is
   begin
      Reset_Title (Glide_Window (Get_Main_Window (Kernel)));
   end On_Project_Changed;

   -------------------
   -- Put_Animation --
   -------------------

   procedure Put_Animation
     (Kernel         : access Kernel_Handle_Record'Class;
      Main_Window    : access Glide_Window_Record'Class;
      File_From_Pref : String)
   is
      File : constant String := Normalize_Pathname
        (File_From_Pref, Get_System_Dir (Kernel) & "/share/gps/");
      Error  : GError;
      Pixbuf : Gdk_Pixbuf;
   begin
      if Main_Window.Animation_Image /= null then
         Destroy (Main_Window.Animation_Image);
         Main_Window.Animation_Image := null;
      end if;

      Trace (Me, "Loading animation " & File);

      if Is_Regular_File (File) then
         Gdk_New_From_File (Main_Window.Animation, File, Error);
         Gtk_New (Main_Window.Animation_Image, Main_Window.Animation);
         Main_Window.Animation_Iter := Get_Iter (Main_Window.Animation);
         Pixbuf := Get_Pixbuf (Main_Window.Animation_Iter);
         Set (Main_Window.Animation_Image, Pixbuf);
         Add (Main_Window.Animation_Frame, Main_Window.Animation_Image);
         Show_All (Main_Window.Animation_Image);
      else
         Trace (Me, "Animation not found");
      end if;
   end Put_Animation;

   -------------------------
   -- Preferences_Changed --
   -------------------------

   procedure Preferences_Changed
     (Kernel : access Kernel_Handle_Record'Class)
   is
      use Glib;
      Win : constant Glide_Window := Glide_Window (Get_Main_Window (Kernel));
      Pos : Gtk_Position_Type;
      Policy : Show_Tabs_Policy_Enum;
   begin
      Gtk.Rc.Parse_String
        ("gtk-font-name=""" &
         To_String (Get_Pref (Kernel, Default_Font)) &
         '"' & ASCII.LF &
         "gtk-can-change-accels=" &
         Integer'Image
           (Boolean'Pos
              (Get_Pref (Kernel, Can_Change_Accels))));

      case Toolbar_Icons_Size'Val (Get_Pref (Kernel, Pref_Toolbar_Style)) is
         when Hide_Toolbar =>
            Set_Child_Visible (Win.Toolbar_Box, False);
            Hide_All (Win.Toolbar_Box);
         when Small_Icons  =>
            Set_Size_Request (Win.Toolbar_Box, -1, -1);
            Set_Child_Visible (Win.Toolbar_Box, True);
            Show_All (Win.Toolbar_Box);
            Set_Icon_Size (Win.Toolbar, Icon_Size_Small_Toolbar);
            Put_Animation
              (Kernel, Win, Get_Pref (Kernel, Animated_Image_Small));
         when Large_Icons  =>
            Set_Size_Request (Win.Toolbar_Box, -1, -1);
            Set_Child_Visible (Win.Toolbar_Box, True);
            Show_All (Win.Toolbar_Box);
            Set_Icon_Size (Win.Toolbar, Icon_Size_Large_Toolbar);
            Put_Animation
              (Kernel, Win, Get_Pref (Kernel, Animated_Image));
      end case;

      if Get_Pref (Kernel, Toolbar_Show_Text) then
         Set_Style (Get_Toolbar (Kernel), Toolbar_Both);
      else
         Set_Style (Get_Toolbar (Kernel), Toolbar_Icons);
      end if;

      case Tabs_Position_Preference'Val
        (Get_Pref (Kernel, Pref_Tabs_Position))
      is
         when Bottom => Pos := Pos_Bottom;
         when Right  => Pos := Pos_Right;
         when Top    => Pos := Pos_Top;
         when Left   => Pos := Pos_Left;
      end case;

      case Tabs_Policy_Enum'Val (Get_Pref (Kernel, Pref_Tabs_Policy)) is
         when Automatic => Policy := Show_Tabs_Policy_Enum'(Automatic);
         when Never     => Policy := Show_Tabs_Policy_Enum'(Never);
         when Always    => Policy := Show_Tabs_Policy_Enum'(Always);
      end case;

      Configure
        (Get_MDI (Kernel),
         Opaque_Resize     => Get_Pref (Kernel, MDI_Opaque),
         Opaque_Move       => Get_Pref (Kernel, MDI_Opaque),
         Close_Floating_Is_Unfloat =>
           not Get_Pref (Kernel, MDI_Destroy_Floats),
         Title_Font        => Get_Pref (Kernel, Default_Font),
         Background_Color  => Get_Pref (Kernel, MDI_Background_Color),
         Title_Bar_Color   => Get_Pref (Kernel, MDI_Title_Bar_Color),
         Focus_Title_Color => Get_Pref (Kernel, MDI_Focus_Title_Color),
         Draw_Title_Bars   => Get_Pref (Kernel, Pref_Draw_Title_Bars),
         Show_Tabs_Policy  => Policy,
         Tabs_Position     => Pos);

      Set_All_Floating_Mode
        (Get_MDI (Kernel), Get_Pref (Kernel, MDI_All_Floating));
   end Preferences_Changed;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize
     (Main_Window      : access Glide_Window_Record'Class;
      Key              : String;
      Menu_Items       : Gtk_Item_Factory_Entry_Array;
      Home_Dir         : String;
      Prefix_Directory : String)
   is
      Box1   : Gtk_Hbox;
   begin
      Gtk_New (Main_Window.Kernel, Gtk_Window (Main_Window), Home_Dir);

      Pref_Draw_Title_Bars := Param_Spec_Boolean
        (Gnew_Boolean
           (Name  => "Window-Draw-Title-Bars",
            Nick  => -"Show title bars",
            Blurb => -("Whether the windows should have their own title bars."
                       & " If this is disabled, then the notebooks tabs will"
                       & " be used to show the current window"),
            Default => True));
      Register_Property
        (Main_Window.Kernel, Param_Spec (Pref_Draw_Title_Bars), -"Windows");

      Pref_Tabs_Policy := Param_Spec_Enum
        (Show_Tabs_Policy_Properties.Gnew_Enum
           (Name  => "Window-Tabs-Policy",
            Nick  => -"Notebook tabs policy",
            Blurb => -"When the notebook tabs should be displayed",
            Default => Automatic));
      Register_Property
        (Main_Window.Kernel, Param_Spec (Pref_Tabs_Policy), -"Windows");

      Pref_Tabs_Position := Param_Spec_Enum
        (Tabs_Position_Properties.Gnew_Enum
           (Name  => "Window-Tabs-Position",
            Nick  => -"Notebook tabs position",
            Blurb => -("Where the tabs should be displayed relative to the"
                       & " notebooks"),
            Default => Bottom));
      Register_Property
        (Main_Window.Kernel, Param_Spec (Pref_Tabs_Position), -"Windows");

      Pref_Toolbar_Style := Param_Spec_Enum
        (Toolbar_Icons_Size_Properties.Gnew_Enum
           (Name    => "General-Toolbar-Style",
            Nick    => -"Tool bar style",
            Blurb   => -("Indicates how the tool bar should be displayed"),
            Default => Large_Icons));
      Register_Property
        (Main_Window.Kernel, Param_Spec (Pref_Toolbar_Style), -"General");

      Animated_Image_Small := Param_Spec_String (Gnew_String
        (Name    => "General-Animated-Image-Small",
         Nick    => -"Animated image (small)",
         Blurb   => -("Animated image used to inform the user about"
                      & " a command in process"),
         Default => "gps-animation-small.gif",
         Flags   => Param_Readable));
      Register_Property
        (Main_Window.Kernel, Param_Spec (Animated_Image_Small), -"General");


      GVD.Main_Window.Initialize (Main_Window, Key, Menu_Items);

      Set_Priorities (Main_Window.Process_Mdi, (Left, Top, Bottom, Right));
      Setup_Toplevel_Window (Main_Window.Process_Mdi, Main_Window);
      Main_Window.Home_Dir := new String'(Home_Dir);
      Main_Window.Prefix_Directory := new String'(Prefix_Directory);
      Main_Window.Standalone := False;

      Gtk_New_Hbox (Box1);
      Pack_Start (Main_Window.Toolbar_Box, Box1);
      Gtk_New (Main_Window.Toolbar, Orientation_Horizontal, Toolbar_Icons);
      Set_Tooltips (Main_Window.Toolbar, True);
      Pack_Start (Box1, Main_Window.Toolbar, True, True);

      Gtk_New (Main_Window.Animation_Frame);
      Set_Shadow_Type (Main_Window.Animation_Frame, Shadow_In);
      Pack_End (Box1, Main_Window.Animation_Frame, False, False);

      Widget_Callback.Connect
        (Main_Window, "destroy",
         Widget_Callback.To_Marshaller (On_Destroy'Access));

      Add_Hook (Main_Window.Kernel, Preferences_Changed_Hook,
                Preferences_Changed'Access);
      Preferences_Changed (Main_Window.Kernel);

      --  Make sure we don't display the toolbar until we have actually loaded
      --  the preferences and checked whether the user wants it or not. This is
      --  to avoid flickering
      Set_Size_Request (Main_Window.Toolbar_Box, -1, 0);
      Set_Child_Visible (Main_Window.Toolbar_Box, False);
      Hide_All (Main_Window.Toolbar_Box);

      Add_Hook (Main_Window.Kernel, Project_Changed_Hook,
                On_Project_Changed'Access);

      Return_Callback.Object_Connect
        (Main_Window, "delete_event",
         Delete_Callback'Access,
         Gtk_Widget (Main_Window),
         After => False);

      --  Support for Win32 WM_DROPFILES drag'n'drop

      Gtk.Dnd.Dest_Set
        (Main_Window, Dest_Default_All, Target_Table_Url, Action_Any);
      Kernel_Callback.Connect
        (Main_Window, "drag_data_received",
         Drag_Data_Received'Access, Kernel_Handle (Main_Window.Kernel));
   end Initialize;

   -------------------
   -- Register_Keys --
   -------------------

   procedure Register_Keys (Main_Window : access Glide_Window_Record'Class) is
      Command : MDI_Child_Selection_Command_Access;
      Command2 : MDI_Window_Actions_Command_Access;
      MDI_Class : constant Class_Type := New_Class
        (Main_Window.Kernel, "MDI");
      MDI_Window_Class : constant Class_Type := New_Class
        (Main_Window.Kernel, "MDIWindow", Get_GUI_Class (Main_Window.Kernel));
   begin
      Command              := new MDI_Child_Selection_Command;
      Command.Kernel       := Main_Window.Kernel;
      Command.Move_To_Next := True;
      Command.Mode         := All_Windows;
      Register_Action
        (Main_Window.Kernel,
         Name        => "Move to next window",
         Command     => Command,
         Description =>
           -("Select the next window in GPS. Any key binding should use a"
             & " modifier such as control for best usage of this function."));
      Bind_Default_Key
        (Kernel      => Main_Window.Kernel,
         Action      => "Move to next window",
         Default_Key => "alt-Tab");

      Command              := new MDI_Child_Selection_Command;
      Command.Kernel       := Main_Window.Kernel;
      Command.Move_To_Next := False;
      Command.Mode         := All_Windows;
      Register_Action
        (Main_Window.Kernel,
         Name        => "Move to previous window",
         Command     => Command,
         Description =>
           -("Select the previous window in GPS. Any key binding should use a"
             & " modifier such as control for best usage of this function."));
      Bind_Default_Key
        (Kernel      => Main_Window.Kernel,
         Action      => "Move to previous window",
         Default_Key => "alt-shift-ISO_Left_Tab");

      Command              := new MDI_Child_Selection_Command;
      Command.Kernel       := Main_Window.Kernel;
      Command.Mode         := Notebook_Windows;
      Command.Move_To_Next := True;
      Register_Action
        (Main_Window.Kernel,
         Name        => "Select other window",
         Command     => Command,
         Description =>
           -("Select the next splitted window in the central area of GPS."));

      Command2        := new MDI_Window_Actions_Command;
      Command2.Kernel := Main_Window.Kernel;
      Command2.Mode   := Split_H;
      Register_Action
        (Main_Window.Kernel,
         Name        => "Split horizontally",
         Command     => Command2,
         Description => -("Split the current window in two horizontally"));

      Command2        := new MDI_Window_Actions_Command;
      Command2.Kernel := Main_Window.Kernel;
      Command2.Mode   := Split_V;
      Register_Action
        (Main_Window.Kernel,
         Name        => "Split vertically",
         Command     => Command2,
         Description => -("Split the current window in two vertically"));

      Command2        := new MDI_Window_Actions_Command;
      Command2.Kernel := Main_Window.Kernel;
      Command2.Mode   := Tile_H;
      Register_Action
        (Main_Window.Kernel,
         Name        => "Tile horizontally",
         Command     => Command2,
         Description =>
           -("Tile the windows in the central area horizontally"));

      Command2        := new MDI_Window_Actions_Command;
      Command2.Kernel := Main_Window.Kernel;
      Command2.Mode   := Tile_V;
      Register_Action
        (Main_Window.Kernel,
         Name        => "Tile vertically",
         Command     => Command2,
         Description =>
           -("Tile the windows in the central area vertically"));

      Command2        := new MDI_Window_Actions_Command;
      Command2.Kernel := Main_Window.Kernel;
      Command2.Mode   := Maximize;
      Register_Action
        (Main_Window.Kernel,
         Name        => "Maximize windows",
         Command     => Command2,
         Description => -("Maximize all windows in the central area"));

      Command2        := new MDI_Window_Actions_Command;
      Command2.Kernel := Main_Window.Kernel;
      Command2.Mode   := Unmaximize;
      Register_Action
        (Main_Window.Kernel,
         Name        => "Unmaximize windows",
         Command     => Command2,
         Description => -("Unmaximize all windows in the central area"));

      Command2        := new MDI_Window_Actions_Command;
      Command2.Kernel := Main_Window.Kernel;
      Command2.Mode   := Single;
      Register_Action
        (Main_Window.Kernel,
         Name        => "Single window",
         Command     => Command2,
         Description => -("Unsplit the central area of GPS, so that only one"
                          & " window is visible"));

      Command2        := new MDI_Window_Actions_Command;
      Command2.Kernel := Main_Window.Kernel;
      Command2.Mode   := Clone;
      Register_Action
        (Main_Window.Kernel,
         Name        => "Clone window",
         Command     => Command2,
         Description =>
         -("Create a duplicate of the current window if possible. Not all"
           & " windows support this operation."));

      Register_Command
        (Main_Window.Kernel, "dialog",
         Minimum_Args => 1,
         Maximum_Args => 1,
         Class         => MDI_Class,
         Static_Method => True,
         Handler      => Default_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "yes_no_dialog",
         Minimum_Args => 1,
         Maximum_Args => 1,
         Class         => MDI_Class,
         Static_Method => True,
         Handler      => Default_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "input_dialog",
         Minimum_Args => 2,
         Maximum_Args => 100,
         Class         => MDI_Class,
         Static_Method => True,
         Handler      => Default_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "save_all",
         Maximum_Args  => 1,
         Class         => MDI_Class,
         Static_Method => True,
         Handler       => Default_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "exit",
         Minimum_Args => Exit_Cmd_Parameters'Length - 1,
         Maximum_Args => Exit_Cmd_Parameters'Length,
         Handler      => Default_Command_Handler'Access);


      Register_Command
        (Main_Window.Kernel, Constructor_Method,
         Class         => MDI_Window_Class,
         Handler       => Default_Window_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "split",
         Class         => MDI_Window_Class,
         Maximum_Args  => 2,
         Handler       => Default_Window_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "iconify",
         Maximum_Args  => 1,
         Class         => MDI_Window_Class,
         Handler       => Default_Window_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "float",
         Maximum_Args  => 1,
         Class         => MDI_Window_Class,
         Handler       => Default_Window_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "dock",
         Class         => MDI_Window_Class,
         Maximum_Args  => 2,
         Handler       => Default_Window_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "single",
         Class         => MDI_Window_Class,
         Handler       => Default_Window_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "raise",
         Class         => MDI_Window_Class,
         Handler       => Default_Window_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "get_child",
         Class          => MDI_Window_Class,
         Handler        => Default_Window_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "next",
         Class          => MDI_Window_Class,
         Maximum_Args   => 1,
         Handler        => Default_Window_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "name",
         Class          => MDI_Window_Class,
         Handler        => Default_Window_Command_Handler'Access);

      Register_Command
        (Main_Window.Kernel, "tile",
         Class         => MDI_Class,
         Maximum_Args  => 1,
         Static_Method => True,
         Handler => Default_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "maximize",
         Class         => MDI_Class,
         Static_Method => True,
         Handler => Default_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "unmaximize",
         Class         => MDI_Class,
         Static_Method => True,
         Handler => Default_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "cascade",
         Class         => MDI_Class,
         Static_Method => True,
         Handler => Default_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "get",
         Class         => MDI_Class,
         Static_Method => True,
         Minimum_Args  => 1,
         Maximum_Args  => 1,
         Handler       => Default_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "get_by_child",
         Class         => MDI_Class,
         Static_Method => True,
         Minimum_Args  => 1,
         Maximum_Args  => 1,
         Handler       => Default_Command_Handler'Access);
      Register_Command
        (Main_Window.Kernel, "current",
         Class         => MDI_Class,
         Static_Method => True,
         Handler       => Default_Command_Handler'Access);
   end Register_Keys;

   ------------------------------------
   -- Default_Window_Command_Handler --
   ------------------------------------

   procedure Default_Window_Command_Handler
     (Data    : in out Callback_Data'Class;
      Command : String)
   is
      Kernel : constant Kernel_Handle := Get_Kernel (Data);
      MDI_Window_Class : constant Class_Type :=
        New_Class (Kernel, "MDIWindow");
      Inst   : constant Class_Instance := Nth_Arg (Data, 1, MDI_Window_Class);
      Child  : constant MDI_Child := MDI_Child (Gtk_Widget'(Get_Data (Inst)));
      Widget : Gtk_Widget;
      Result : Class_Instance;
   begin
      if Child = null then
         Set_Error_Msg (Data, "MDIWindow no longer exists");

      elsif Command = Constructor_Method then
         Set_Error_Msg (Data, "Cannot build instances of MDIWindow");

      elsif Command = "split" then
         Name_Parameters (Data, Split_Cmd_Parameters);
         if Get_State (Child) = Normal then
            Set_Focus_Child (Child);
            if Nth_Arg (Data, 2, True) then
               Split (Get_MDI (Kernel),
                      Orientation       => Orientation_Vertical,
                      Reuse_If_Possible => Nth_Arg (Data, 3, False),
                      After             => False);
            else
               Split (Get_MDI (Kernel),
                      Orientation       => Orientation_Horizontal,
                      Reuse_If_Possible => Nth_Arg (Data, 3, False),
                      After             => False);
            end if;
         end if;

      elsif Command = "iconify" then
         Name_Parameters (Data, Iconify_Cmd_Parameters);
         Minimize_Child (Child, Nth_Arg (Data, 2, True));

      elsif Command = "float" then
         Name_Parameters (Data, Float_Cmd_Parameters);
         Float_Child (Child, Nth_Arg (Data, 2, True));

      elsif Command = "dock" then
         Name_Parameters (Data, Dock_Cmd_Parameters);
         Set_Dock_Side (Child, Dock_Side'Value (Nth_Arg (Data, 3, "bottom")));
         Dock_Child (Child, Nth_Arg (Data, 2, True));

      elsif Command = "single" then
         if Get_State (Child) = Normal then
            Set_Focus_Child (Child);
            Single_Window (Get_MDI (Kernel));
         end if;

      elsif Command = "raise" then
         Raise_Child (Child, Give_Focus => True);

      elsif Command = "name" then
         Set_Return_Value (Data, Get_Title (Child));

      elsif Command = "next" then
         Name_Parameters (Data, Next_Cmd_Parameters);
         declare
            Child2 : MDI_Child;
            Iter   : Child_Iterator := First_Child (Get_MDI (Kernel));
            Return_Next : Boolean := False;
            Visible_Only : constant Boolean := Nth_Arg (Data, 2, True);
         begin
            loop
               Child2 := Get (Iter);

               if Child2 = null then
                  Iter := First_Child (Get_MDI (Kernel));
                  Return_Next := True;
                  Child2 := Get (Iter);
               end if;

               exit when Return_Next
                 and then (not Visible_Only or else Is_Raised (Child2));

               if Child2 = Child then
                  exit when Return_Next;  --  We already traversed all
                  Return_Next := True;
               end if;

               Next (Iter);
            end loop;

            Result := New_Instance (Get_Script (Data), MDI_Window_Class);
            Set_Data (Result, Gtk_Widget (Child2));
            Set_Return_Value (Data, Result);
            Free (Result);
         end;

      elsif Command = "get_child" then
         Widget := Get_Widget (Child);
         Result := Get_Instance (Widget);
         if Result /= null then
            Set_Return_Value (Data, Result);
         else
            Result := New_Instance (Get_Script (Data), Get_GUI_Class (Kernel));
            Set_Data (Result, Widget);
            Set_Return_Value (Data, Result);
            Free (Result);
         end if;
      end if;

      Free (Inst);
   end Default_Window_Command_Handler;

   -----------------------------
   -- Default_Command_Handler --
   -----------------------------

   procedure Default_Command_Handler
     (Data    : in out Callback_Data'Class;
      Command : String)
   is
      Kernel : constant Kernel_Handle := Get_Kernel (Data);
      MDI_Window_Class : Class_Type;
      Child  : MDI_Child;
      Inst   : Class_Instance;
   begin
      if Command = "exit" then
         Name_Parameters (Data, Exit_Cmd_Parameters);
         Quit (Glide_Window (Get_Main_Window (Kernel)),
               Force => Nth_Arg (Data, 1, False));
      elsif Command = "save_all" then
         Name_Parameters (Data, Save_Windows_Parameters);

         if not Save_MDI_Children
           (Kernel, No_Children, Nth_Arg (Data, 1, False))
         then
            Set_Error_Msg (Data, -"Cancelled by user");
         end if;

      elsif Command = "tile" then
         Name_Parameters (Data, Tile_Cmd_Parameters);
         if Nth_Arg (Data, 1, True) then
            Tile_Vertically (Get_MDI (Kernel));
         else
            Tile_Horizontally (Get_MDI (Kernel));
         end if;

      elsif Command = "maximize" then
         Maximize_Children (Get_MDI (Kernel), True);

      elsif Command = "unmaximize" then
         Maximize_Children (Get_MDI (Kernel), False);

      elsif Command = "cascade" then
         Cascade_Children (Get_MDI (Kernel));

      elsif Command = "get"
        or else Command = "get_by_child"
        or else Command = "current"
      then
         if Command = "get" then
            Name_Parameters (Data, Get_Cmd_Parameters);
            Child := Find_MDI_Child_By_Name
              (Get_MDI (Kernel), Nth_Arg (Data, 1));
         elsif Command = "get_by_child" then
            Name_Parameters (Data, Get_By_Child_Cmd_Parameters);
            Child := Find_MDI_Child
              (Get_MDI (Kernel),
               Widget => Get_Data (Nth_Arg (Data, 1, Get_GUI_Class (Kernel))));
         else
            Child := Get_Focus_Child (Get_MDI (Kernel));
         end if;

         if Child = null then
            Set_Error_Msg (Data, "No such window");
         else
            MDI_Window_Class := New_Class (Kernel, "MDIWindow");
            Inst := New_Instance (Get_Script (Data), MDI_Window_Class);
            Set_Data (Inst, Gtk_Widget (Child));
            Set_Return_Value (Data, Inst);
            Free (Inst);
         end if;

      elsif Command = "dialog" then
         Name_Parameters (Data, Dialog_Cmd_Parameters);

         declare
            Result : Message_Dialog_Buttons;
            pragma Unreferenced (Result);
         begin
            Result := Message_Dialog
              (Msg     => Nth_Arg (Data, 1),
               Buttons => Button_OK,
               Justification => Justify_Left,
               Parent  => Get_Current_Window (Kernel));
         end;

      elsif Command = "yes_no_dialog" then
         Name_Parameters (Data, Dialog_Cmd_Parameters);
         Set_Return_Value
           (Data, Message_Dialog
            (Msg           => Nth_Arg (Data, 1),
             Buttons       => Button_Yes + Button_No,
             Justification => Justify_Left,
             Dialog_Type   => Confirmation,
             Parent        => Get_Current_Window (Kernel)) = Button_Yes);

      elsif Command = "input_dialog" then
         declare
            Dialog : Gtk_Dialog;
            Label  : Gtk_Label;
            Group  : Gtk_Size_Group;
            Button : Gtk_Widget;

            type Ent_Array
               is array (2 .. Number_Of_Arguments (Data)) of Gtk_Entry;
            Ent : Ent_Array;

            procedure Create_Entry (N : Natural);
            --  Create the Nth entry. N must be in Ent_Array'Range.

            ------------------
            -- Create_Entry --
            ------------------

            procedure Create_Entry (N : Natural) is
               Arg   : constant String := Nth_Arg (Data, N);
               Index : Natural := Arg'First;
               Hbox  : Gtk_Hbox;
            begin
               Gtk_New_Hbox (Hbox, Homogeneous => False);
               Pack_Start (Get_Vbox (Dialog), Hbox, Padding => 3);

               while Index <= Arg'Last loop
                  exit when Arg (Index) = '=';

                  Index := Index + 1;
               end loop;

               Gtk_New (Label, Arg (Arg'First .. Index - 1) & ':');
               Set_Alignment (Label, 0.0, 0.5);
               Add_Widget (Group, Label);
               Pack_Start (Hbox, Label, Expand => False, Padding => 3);

               Gtk_New (Ent (N));
               Set_Text (Ent (N), Arg (Index + 1 .. Arg'Last));

               Set_Activates_Default (Ent (N),  True);
               Pack_Start (Hbox, Ent (N), Padding => 10);
            end Create_Entry;

         begin
            Name_Parameters (Data, Input_Dialog_Cmd_Parameters);

            Gtk_New (Label);
            Set_Markup (Label, Nth_Arg (Data, 1));

            Gtk_New
              (Dialog,
               Title  => Get_Text (Label),
               Parent => Get_Current_Window (Kernel),
               Flags  => Modal);

            Set_Alignment (Label, 0.0, 0.5);
            Pack_Start
              (Get_Vbox (Dialog), Label, Expand => True, Padding => 10);

            Gtk_New (Group);

            for Num in Ent'Range loop
               Create_Entry (Num);
            end loop;

            Button := Add_Button (Dialog, Stock_Ok, Gtk_Response_OK);
            Grab_Default (Button);
            Button := Add_Button (Dialog, Stock_Cancel, Gtk_Response_Cancel);

            Show_All (Dialog);

            Set_Return_Value_As_List (Data);

            if Run (Dialog) = Gtk_Response_OK then
               for Num in Ent'Range loop
                  Set_Return_Value (Data, Get_Text (Ent (Num)));
               end loop;
            end if;

            Destroy (Dialog);
         end;
      end if;
   end Default_Command_Handler;

   -------------
   -- Execute --
   -------------

   function Execute
     (Command : access MDI_Child_Selection_Command;
      Context : Interactive_Command_Context) return Command_Return_Type is
   begin
      if Command.Mode = Notebook_Windows then
         Check_Interactive_Selection_Dialog
           (Get_MDI (Command.Kernel), null,
            Move_To_Next => Command.Move_To_Next,
            Visible_In_Central_Only => Command.Mode = Notebook_Windows);
      else
         Check_Interactive_Selection_Dialog
           (Get_MDI (Command.Kernel), Context.Event,
            Move_To_Next => Command.Move_To_Next,
            Visible_In_Central_Only => Command.Mode = Notebook_Windows);
      end if;
      return Success;
   end Execute;

   --------------
   -- GPS_Name --
   --------------

   function GPS_Name (Window : access Glide_Window_Record) return String is
   begin
      if Window.Public_Version then
         return "GPS";
      else
         return "GPS Pro";
      end if;
   end GPS_Name;

   ----------------
   -- On_Destroy --
   ----------------

   procedure On_Destroy (Main_Window : access Gtk_Widget_Record'Class) is
      Win : constant Glide_Window := Glide_Window (Main_Window);

      use Glib;
   begin
      Free (Win.Home_Dir);
      Free (Win.Prefix_Directory);
      Unref (Win.Animation);
      Unref (Win.Animation_Iter);

      if Main_Level > 0 then
         Main_Quit;
      end if;
   end On_Destroy;

   ------------------
   -- Load_Desktop --
   ------------------

   procedure Load_Desktop (Window : access Glide_Window_Record'Class) is
      Was_Loaded : Boolean;
      pragma Unreferenced (Was_Loaded);
   begin
      Was_Loaded := Load_Desktop (Window.Kernel);
   end Load_Desktop;

   -----------------
   -- Reset_Title --
   -----------------

   procedure Reset_Title
     (Window : access Glide_Window_Record;
      Info   : String := "") is
   begin
      if Info = "" then
         Set_Title (Window, GPS_Name (Window) &
                    (-" - GNAT Programming System (project: ") &
                    Project_Name (Get_Project (Window.Kernel)) & ')');
      else
         Set_Title (Window, GPS_Name (Window) &
                    (-" - GNAT Programming System (project: ") &
                    Project_Name (Get_Project (Window.Kernel)) &
                    ") - " & Info);
      end if;
   end Reset_Title;

end Glide_Main_Window;
