-----------------------------------------------------------------------
--               GtkAda - Ada95 binding for Gtk+/Gnome               --
--                                                                   --
--                 Copyright (C) 2001-2002 ACT-Europe                --
--                                                                   --
-- This library is free software; you can redistribute it and/or     --
-- modify it under the terms of the GNU General Public               --
-- License as published by the Free Software Foundation; either      --
-- version 2 of the License, or (at your option) any later version.  --
--                                                                   --
-- This library is distributed in the hope that it will be useful,   --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of    --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details.                          --
--                                                                   --
-- You should have received a copy of the GNU General Public         --
-- License along with this library; if not, write to the             --
-- Free Software Foundation, Inc., 59 Temple Place - Suite 330,      --
-- Boston, MA 02111-1307, USA.                                       --
--                                                                   --
-- As a special exception, if other files instantiate generics from  --
-- this unit, or you link this unit with other files to produce an   --
-- executable, this  unit  does not  by itself cause  the resulting  --
-- executable to be covered by the GNU General Public License. This  --
-- exception does not however invalidate any other reasons why the   --
-- executable file  might be covered by the  GNU Public License.     --
-----------------------------------------------------------------------

with Glib;                      use Glib;
with Glib.Convert;              use Glib.Convert;
with Gtk;                       use Gtk;
with Gdk;                       use Gdk;
with Gdk.Types.Keysyms;         use Gdk.Types.Keysyms;
with Gtk.Widget;                use Gtk.Widget;
with Gtk.Arguments;             use Gtk.Arguments;
with Gtk.Enums;                 use Gtk.Enums;
with Gtk.Stock;                 use Gtk.Stock;
with Gtk.Main;
with Gtk.Ctree;                 use Gtk.Ctree;
with Gtk.Paned;                 use Gtk.Paned;
with Gtk.Hbutton_Box;           use Gtk.Hbutton_Box;
with Gtk.Toolbar;               use Gtk.Toolbar;
with Gdk.Event;                 use Gdk.Event;
with Gdk.Pixmap;                use Gdk.Pixmap;
with Gdk.Bitmap;                use Gdk.Bitmap;
with Gdk.Color;                 use Gdk.Color;
with GUI_Utils;                 use GUI_Utils;

with Gtkada.Types;              use Gtkada.Types;
with Gtkada.Handlers;           use Gtkada.Handlers;
with Gtkada.Intl;               use Gtkada.Intl;
with Interfaces.C.Strings;

with File_Utils;                use File_Utils;
with GUI_Utils;                 use GUI_Utils;
with Traces;                    use Traces;

with GNAT.Regexp;               use GNAT.Regexp;
with GNAT.Directory_Operations; use GNAT.Directory_Operations;
with Ada.Characters.Handling;   use Ada.Characters.Handling;
with Ada.Exceptions;            use Ada.Exceptions;

with Histories;                 use Histories;

package body Gtkada.File_Selector is

   Me : constant Debug_Handle := Create ("Gtkada.File_Selector");

   Directories_Hist_Key : constant Histories.History_Key := "directories";
   --  Key used in the history

   -----------------------
   -- Local subprograms --
   -----------------------

   procedure Change_Directory
     (Win : access File_Selector_Window_Record'Class;
      Dir : String);
   --  Called every time that the contents of a new directory should be
   --  displayed in the File_Explorer. Dir is the absolute pathname to
   --  that directory.

   procedure Refresh_Files
     (Win : access File_Selector_Window_Record'Class);

   function Read_File
     (Win : File_Selector_Window_Access) return Boolean;
   --  Read one file from the current directory and insert it in Files.

   function Display_File
     (Win : File_Selector_Window_Access) return Boolean;
   --  This function gets one entry from Win.Remaining_Files, applies
   --  a filter to it, and displays the corresponding information in the
   --  file list.

   type Regexp_Filter_Record is new File_Filter_Record with record
      Pattern : Regexp;
   end record;

   type Regexp_Filter is access all Regexp_Filter_Record'Class;

   function Regexp_File_Filter
     (Pattern : String;
      Name    : String) return Regexp_Filter;
   --  Return a new filter that only shows files matching pattern.
   --  New memory is allocated, that will be freed automatically by the file
   --  selector where the filter is registered.
   --  If Name is not null, use it instead of Pattern for the name of the
   --  filter.

   procedure Use_File_Filter
     (Filter    : access Regexp_Filter_Record;
      Win       : access File_Selector_Window_Record'Class;
      Dir       : String;
      File      : String;
      State     : out File_State;
      Pixmap    : out Gdk.Pixmap.Gdk_Pixmap;
      Mask      : out Gdk.Bitmap.Gdk_Bitmap;
      Text      : out GNAT.OS_Lib.String_Access);
   --  See spec for more details on this dispatching routine.

   ---------------
   -- Callbacks --
   ---------------

   procedure Realized
     (Object : access Gtk_Widget_Record'Class);
   --  ???

   procedure On_Back_Button_Clicked
     (Object : access Gtk_Widget_Record'Class);
   --  ???

   procedure On_Up_Button_Clicked
     (Object : access Gtk_Widget_Record'Class);
   --  ???

   procedure On_Home_Button_Clicked
     (Object : access Gtk_Widget_Record'Class);
   --  ???

   procedure On_Refresh_Button_Clicked
     (Object : access Gtk_Widget_Record'Class);
   --  ???

   procedure On_Forward_Button_Clicked
     (Object : access Gtk_Widget_Record'Class);
   --  ???

   procedure Directory_Selected (Object : access Gtk_Widget_Record'Class);
   --  ???

   procedure Filter_Selected
     (Object : access Gtk_Widget_Record'Class);
   --  ???

   procedure On_Location_Combo_Entry_Activate
     (Object : access Gtk_Widget_Record'Class);
   --  ???

   procedure On_Explorer_Tree_Select_Row
     (Object : access Gtk_Widget_Record'Class);
   --  ???

   procedure On_File_List_End_Selection
     (Object : access Gtk_Widget_Record'Class; Args : Gtk_Args);
   --  ???

   procedure On_Selection_Entry_Changed
     (Object : access Gtk_Widget_Record'Class);
   --  ???

   procedure On_Ok_Button_Clicked
     (Object : access Gtk_Widget_Record'Class);
   --  ???

   procedure On_Cancel_Button_Clicked
     (Object : access Gtk_Widget_Record'Class);
   --  ???

   procedure On_Destroy
     (Object : access Gtk_Widget_Record'Class);
   --  ???

   function On_File_List_Key_Press_Event
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args) return Boolean;
   --  ???

   function On_Selection_Entry_Key_Press_Event
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args) return Boolean;
   --  ???

   function On_Location_Entry_Key_Press_Event
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args) return Boolean;
   --  ???

   procedure On_Display_Idle_Destroy
     (Win : in out File_Selector_Window_Access);
   --  Callback used to destroy the display idle loop.

   procedure On_Read_Idle_Destroy
     (Win : in out File_Selector_Window_Access);
   --  Callback used to destroy the read idle loop.

   ------------------------
   -- Regexp_File_Filter --
   ------------------------

   function Regexp_File_Filter
     (Pattern : String;
      Name    : String) return Regexp_Filter
   is
      Filter : Regexp_Filter := new Regexp_Filter_Record;
   begin
      if Name = "" then
         Filter.Label := new String'(Pattern);
      else
         Filter.Label := new String'(Name);
      end if;

      Filter.Pattern :=
        Compile
          (Pattern        => Pattern,
           Glob           => True,
           Case_Sensitive => Filenames_Are_Case_Sensitive);
      return Filter;
   end Regexp_File_Filter;

   ---------------------
   -- Use_File_Filter --
   ---------------------

   procedure Use_File_Filter
     (Filter    : access Regexp_Filter_Record;
      Win       : access File_Selector_Window_Record'Class;
      Dir       : String;
      File      : String;
      State     : out File_State;
      Pixmap    : out Gdk.Pixmap.Gdk_Pixmap;
      Mask      : out Gdk.Bitmap.Gdk_Bitmap;
      Text      : out GNAT.OS_Lib.String_Access)
   is
      pragma Unreferenced (Dir, Win);
   begin
      Text   := null;
      Pixmap := null;
      Mask   := null;

      if Match (File, Filter.Pattern) then
         State := Normal;
      else
         State := Invisible;
      end if;
   end Use_File_Filter;

   -----------------------------
   -- On_Display_Idle_Destroy --
   -----------------------------

   procedure On_Display_Idle_Destroy
     (Win : in out File_Selector_Window_Access) is
   begin
      Win.Display_Idle_Handler := 0;
   end On_Display_Idle_Destroy;

   ---------------------
   -- On_Idle_Destroy --
   ---------------------

   procedure On_Read_Idle_Destroy (Win : in out File_Selector_Window_Access) is
   begin
      Win.Read_Idle_Handler := 0;
   end On_Read_Idle_Destroy;

   -------------------
   -- Get_Selection --
   -------------------

   function Get_Selection
     (Dialog : access File_Selector_Window_Record) return String is
   begin
      if Dialog.Selection_Entry = null
        or else Get_Text (Dialog.Selection_Entry) = ""
      then
         return "";
      else
         return Normalize_Pathname
           (Dialog.Current_Directory.all &
            Locale_From_UTF8 (Get_Text (Dialog.Selection_Entry)));
      end if;
   end Get_Selection;

   -------------------
   -- Get_Ok_Button --
   -------------------

   function Get_Ok_Button
     (File_Selection : access File_Selector_Window_Record)
      return Gtk.Button.Gtk_Button is
   begin
      return File_Selection.Ok_Button;
   end Get_Ok_Button;

   -----------------------
   -- Get_Cancel_Button --
   -----------------------

   function Get_Cancel_Button
     (File_Selection : access File_Selector_Window_Record)
      return Gtk.Button.Gtk_Button is
   begin
      return File_Selection.Cancel_Button;
   end Get_Cancel_Button;

   -----------------
   -- Select_File --
   -----------------

   function Select_File
     (Title             : String  := "Select a file";
      Base_Directory    : String  := "";
      File_Pattern      : String  := "";
      Pattern_Name      : String  := "";
      Default_Name      : String  := "";
      Use_Native_Dialog : Boolean := False;
      History           : Histories.History := null) return String
   is
      function NativeFileSelection
        (Title       : String;
         Basedir     : String;
         Filepattern : String;
         Patternname : String;
         Defaultname : String;
         Style       : Integer) return Chars_Ptr;
      pragma Import (C, NativeFileSelection, "NativeFileSelection");

      function NativeFileSelectionSupported return Integer;
      pragma Import
        (C, NativeFileSelectionSupported, "NativeFileSelectionSupported");

      Pos_Mouse     : constant := 2;
      File_Selector : File_Selector_Window_Access;
      S             : Chars_Ptr;

      procedure c_free (S : Chars_Ptr);
      pragma Import (C, c_free, "free");

   begin
      if Use_Native_Dialog and then NativeFileSelectionSupported /= 0 then
         S := NativeFileSelection
           (Title & ASCII.NUL,
            Base_Directory & ASCII.NUL,
            File_Pattern & ASCII.NUL,
            Pattern_Name & ASCII.NUL,
            Default_Name & ASCII.NUL,
            Pos_Mouse);

         declare
            Val : constant String := Interfaces.C.Strings.Value (S);
         begin
            c_free (S);
            return Val;
         end;
      end if;

      Gtk_New
        (File_Selector, (1 => Directory_Separator), Base_Directory, Title,
         History => History);

      if Default_Name /= "" then
         Set_Text
           (File_Selector.Selection_Entry, Locale_To_UTF8 (Default_Name));
      end if;

      if File_Pattern /= "" then
         Register_Filter
           (File_Selector,
            Regexp_File_Filter (File_Pattern, Pattern_Name));
      end if;

      return Select_File (File_Selector);
   end Select_File;

   function Select_File
     (File_Selector : File_Selector_Window_Access) return String
   is
      Filter_A : Filter_Show_All_Access := new Filter_Show_All;
   begin
      pragma Assert (File_Selector /= null);

      Filter_A.Label := new String'(-"All files");

      Register_Filter (File_Selector, Filter_A);
      Set_Modal (File_Selector, True);

      Widget_Callback.Object_Connect
        (File_Selector.Ok_Button, "clicked",
         Widget_Callback.To_Marshaller (On_Ok_Button_Clicked'Access),
         File_Selector);
      Widget_Callback.Object_Connect
        (File_Selector.Cancel_Button, "clicked",
         Widget_Callback.To_Marshaller (On_Cancel_Button_Clicked'Access),
         File_Selector);

      Show_All (File_Selector);
      Grab_Default (File_Selector.Ok_Button);

      File_Selector.Own_Main_Loop := True;

      Gtk.Main.Main;

      if File_Selector.Current_Directory = null then
         return "";
      else
         declare
            File : constant String := Get_Selection (File_Selector);
         begin
            Destroy (File_Selector);
            return File;
         end;
      end if;
   end Select_File;

   ----------------------
   -- Select_Directory --
   ----------------------

   function Select_Directory
     (Title             : String := "Select a directory";
      Base_Directory    : String := "";
      Use_Native_Dialog : Boolean := False;
      History           : Histories.History := null) return String
   is
      pragma Unreferenced (Use_Native_Dialog);

      File_Selector_Window : File_Selector_Window_Access;
   begin
      Gtk_New
        (File_Selector_Window,
         (1 => Directory_Separator), Base_Directory, Title, False, History);
      return Select_Directory (File_Selector_Window);
   end Select_Directory;

   function Select_Directory
     (File_Selector : File_Selector_Window_Access) return String
   is
      Filter_A : Filter_Show_All_Access := new Filter_Show_All;
   begin
      pragma Assert (File_Selector /= null);

      Filter_A.Label := new String'(-"All files");

      Register_Filter (File_Selector, Filter_A);
      Set_Modal (File_Selector, True);

      Widget_Callback.Object_Connect
        (File_Selector.Ok_Button, "clicked",
         Widget_Callback.To_Marshaller (On_Ok_Button_Clicked'Access),
         File_Selector);
      Widget_Callback.Object_Connect
        (File_Selector.Cancel_Button, "clicked",
         Widget_Callback.To_Marshaller (On_Cancel_Button_Clicked'Access),
         File_Selector);

      Show_All (File_Selector);
      File_Selector.Own_Main_Loop := True;

      Gtk.Main.Main;

      if File_Selector.Current_Directory = null then
         return "";
      else
         declare
            File : constant String := Normalize_Pathname
              (Locale_From_UTF8 (Get_Text (File_Selector.Selection_Entry)));
         begin
            Destroy (File_Selector);
            return File;
         end;
      end if;
   end Select_Directory;

   --------------
   -- Realized --
   --------------

   procedure Realized (Object : access Gtk_Widget_Record'Class) is
      Win : constant File_Selector_Window_Access :=
        File_Selector_Window_Access (Get_Toplevel (Object));
   begin
      Refresh_Files (Win);
   end Realized;

   ------------------
   -- Display_File --
   ------------------

   function Display_File (Win : File_Selector_Window_Access) return Boolean is
      Text        : String_Access;
      State       : File_State;
      Pixmap      : Gdk.Pixmap.Gdk_Pixmap;
      Mask        : Gdk.Bitmap.Gdk_Bitmap;
      Current_Row : Gint;
      Style       : Gtk_Style;
      Strings     : Chars_Ptr_Array (1 .. 3);

   begin
      if Win.Current_Directory = null
        or else Win.Remaining_Files = String_List.Null_Node
      then
         return False;
      end if;

      Use_File_Filter
        (Win.Current_Filter,
         Win,
         Win.Current_Directory.all,
         Data (Win.Remaining_Files),
         State,
         Pixmap,
         Mask,
         Text);

      Strings := "" + "" + "";

      case State is
         when Invisible =>
            Style := null;

         when Normal =>
            Current_Row := Append (Win.File_List, Strings);
            Style := Win.Normal_Style;

         when Highlighted =>
            Current_Row := Append (Win.File_List, Strings);
            Style := Win.Highlighted_Style;

         when Insensitive =>
            Current_Row := Append (Win.File_List, Strings);
            Style := Win.Insensitive_Style;
            Set_Selectable (Win.File_List, Current_Row, False);
      end case;

      if Style /= null then
         Set_Row_Style (Win.File_List, Current_Row, Style);
         Set_Text (Win.File_List, Current_Row, 1,
                   Locale_To_UTF8 (Data (Win.Remaining_Files)));

         if Text /= null then
            Set_Text (Win.File_List, Current_Row, 2,
                      Locale_To_UTF8 (Text.all));
         end if;

         if Pixmap /= Null_Pixmap then
            Set_Pixmap (Win.File_List, Current_Row, 0, Pixmap, Mask);
         end if;
      end if;

      Free (Text);
      Free (Strings);
      Win.Remaining_Files := Next (Win.Remaining_Files);

      return Win.Remaining_Files /= String_List.Null_Node;
   end Display_File;

   ---------------
   -- Read_File --
   ---------------

   function Read_File (Win : File_Selector_Window_Access) return Boolean is
      Buffer : String (1 .. 4096);
      Last   : Natural;
      Prev   : String_List.List_Node;
      Node   : String_List.List_Node;

      use String_List;

   begin
      if Win.Current_Directory = null then
         return False;
      end if;

      if not Win.Current_Directory_Is_Open then
         return False;
      end if;

      Read (Win.Current_Directory_Id.all, Buffer, Last);

      if Last = 0 then
         Close (Win.Current_Directory_Id.all);
         Win.Current_Directory_Is_Open := False;

         Clear (Win.File_List);

         --  Register the function that will fill the list in the background.

         Win.Remaining_Files := First (Win.Files);

         if Win.Display_Idle_Handler /= 0 then
            Idle_Remove (Win.Display_Idle_Handler);
         end if;

         Win.Display_Idle_Handler :=
           Add (Display_File'Access,
                Win,
                Destroy => On_Display_Idle_Destroy'Access);

         return False;

      elsif Is_Directory (Win.Current_Directory.all & Buffer (1 .. Last)) then
         null;
         --  ??? or should we display directories in the File_List ?

      else
         Node := First (Win.Files);
         Prev := String_List.Null_Node;

         while Node /= String_List.Null_Node loop
            if Buffer (1 .. Last) < Data (Node) then
               Append (Win.Files, Prev, Buffer (1 .. Last));
               return True;
            end if;

            Prev := Node;
            Node := Next (Node);
         end loop;

         Append (Win.Files, Buffer (1 .. Last));
      end if;

      return True;
   end Read_File;

   ---------------------
   -- Register_Filter --
   ---------------------

   procedure Register_Filter
     (Win    : access File_Selector_Window_Record;
      Filter : access File_Filter_Record'Class) is
   begin
      Append (Win.Filters, File_Filter (Filter));
      Add_Unique_Combo_Entry (Win.Filter_Combo, Filter.Label.all);
   end Register_Filter;

   ---------------------
   -- Use_File_Filter --
   ---------------------

   procedure Use_File_Filter
     (Filter    : access Filter_Show_All;
      Win       : access File_Selector_Window_Record'Class;
      Dir       : String;
      File      : String;
      State     : out File_State;
      Pixmap    : out Gdk.Pixmap.Gdk_Pixmap;
      Mask      : out Gdk.Bitmap.Gdk_Bitmap;
      Text      : out String_Access)
   is
      pragma Unreferenced (File, Dir, Win, Filter);
   begin
      State  := Normal;
      Mask   := Gdk.Bitmap.Null_Bitmap;
      Pixmap := Gdk.Pixmap.Null_Pixmap;
      Text   := new String'("");
   end Use_File_Filter;

   -------------------
   -- Refresh_Files --
   -------------------

   procedure Refresh_Files (Win : access File_Selector_Window_Record'Class) is
      Dir     : constant String := Win.Current_Directory.all;
      Filter  : File_Filter := null;
      Strings : Chars_Ptr_Array (1 .. 3);

   begin
      if Get_Window (Win) = null
        or else Win.File_List = null
        or else Dir = ""
      then
         return;
      end if;

      Set_Busy_Cursor (Get_Window (Win), True, True);
      Clear (Win.File_List);
      Free (Win.Files);
      Win.Remaining_Files := String_List.Null_Node;

      --  Find out which filter to use.

      declare
         use Filter_List;

         S : constant String :=
           Locale_From_UTF8 (Get_Text (Win.Filter_Combo_Entry));
         C : Filter_List.List_Node := First (Win.Filters);

      begin
         while C /= Filter_List.Null_Node loop
            if Data (C).Label.all = S then
               Filter := Data (C);
               exit;
            else
               C := Next (C);
            end if;
         end loop;
      end;

      if Filter = null then
         Set_Busy_Cursor (Get_Window (Win), False, False);
         return;
      end if;

      Strings := "" + (-"Opening ... ") + "";
      Insert (Win.File_List, -1, Strings);
      Free (Strings);
      Win.Current_Filter := Filter;

      --  Fill the File_List.

      begin
         if Win.Current_Directory_Is_Open then
            Close (Win.Current_Directory_Id.all);
            Win.Current_Directory_Is_Open := False;
         end if;

         GNAT.Directory_Operations.Open (Win.Current_Directory_Id.all, Dir);
         Win.Current_Directory_Is_Open := True;

         if Win.Read_Idle_Handler /= 0 then
            Idle_Remove (Win.Read_Idle_Handler);
         end if;

         Win.Read_Idle_Handler
           := Add (Read_File'Access,
                   File_Selector_Window_Access (Win),
                   Destroy => On_Read_Idle_Destroy'Access);

      exception
         when Directory_Error =>
            Clear (Win.File_List);
            Strings := "" + (-"Could not open " & Dir) + "";
            Insert (Win.File_List, -1, Strings);
            Free (Strings);
      end;

      Set_Busy_Cursor (Get_Window (Win), False, False);
   end Refresh_Files;

   ----------------------
   -- Change_Directory --
   ----------------------

   procedure Change_Directory
     (Win : access File_Selector_Window_Record'Class;
      Dir : String) is
   begin
      --  If the new directory is not the one currently shown in the File_List,
      --  then update the File_List.

      if Dir /= ""
        and then Win.Current_Directory.all /= Normalize_Pathname (Dir)
      then
         Free (Win.Current_Directory);

         if Dir = -"Drives" then
            Win.Current_Directory := new String'("");
         else
            Win.Current_Directory := new String'(Normalize_Pathname (Dir));
         end if;

         --  If we are currently moving through the history,
         --  do not append items to the Location_Combo.

         if Win.Moving_Through_History then
            Win.Moving_Through_History := False;
         else
            Push (Win.Past_History,
                  new String'(Locale_From_UTF8
                                (Get_Text (Win.Location_Combo_Entry))));
            Clear (Win.Future_History);
            Set_Sensitive (Win.Back_Button);
            Set_Sensitive (Win.Forward_Button, False);

            Add_Unique_Combo_Entry (Win.Location_Combo, Dir);

            if Win.History /= null then
               Add_To_History (Win.History.all, "directories", Dir);
            end if;
         end if;

         if Locale_From_UTF8 (Get_Text (Win.Location_Combo_Entry)) /= Dir then
            Set_Text (Win.Location_Combo_Entry, Locale_To_UTF8 (Dir));
         end if;

         --  If the new directory is not the one currently shown
         --  in the Explorer_Tree, then update the Explorer_Tree.

         if Dir /= Get_Selection (Win.Explorer_Tree) then
            Show_Directory (Win.Explorer_Tree,
                            Normalize_Pathname (Dir),
                            Get_Window (Win));
         end if;

         if Win.File_List = null then
            Set_Text (Win.Selection_Entry, Locale_To_UTF8 (Dir));
            Set_Position (Win.Selection_Entry, Dir'Length);
         else
            Refresh_Files (Win);
         end if;
      end if;
   end Change_Directory;

   ----------------------------
   -- On_Back_Button_Clicked --
   ----------------------------

   procedure On_Back_Button_Clicked
     (Object : access Gtk_Widget_Record'Class)
   is
      Win : constant File_Selector_Window_Access :=
        File_Selector_Window_Access (Get_Toplevel (Object));
      S   : String_Access;

   begin
      Pop (Win.Past_History, S);

      if Is_Empty (Win.Past_History) then
         Set_Sensitive (Win.Back_Button, False);
      end if;

      if Is_Empty (Win.Future_History) then
         Set_Sensitive (Win.Forward_Button);
      end if;

      Push (Win.Future_History,
            new String'(Locale_From_UTF8
                          (Get_Text (Win.Location_Combo_Entry))));

      Set_Text (Win.Location_Combo_Entry, Locale_To_UTF8 (S.all));
      Win.Moving_Through_History := True;
      Show_Directory (Win.Explorer_Tree, S.all);
      Free (S);

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
         Free (S);
   end On_Back_Button_Clicked;

   ----------------------------
   -- On_Home_Button_Clicked --
   ----------------------------

   procedure On_Home_Button_Clicked
     (Object : access Gtk_Widget_Record'Class)
   is
      Win : constant File_Selector_Window_Access :=
        File_Selector_Window_Access (Get_Toplevel (Object));

      H   : String_Access := Getenv ("HOME");
   begin
      if H.all /= "" then
         Change_Directory (Win, Normalize_Pathname (H.all));
      else
         Change_Directory (Win, Win.Home_Directory.all);
      end if;

      Free (H);

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Home_Button_Clicked;

   --------------------------
   -- On_Up_Button_Clicked --
   --------------------------

   procedure On_Up_Button_Clicked
     (Object : access Gtk_Widget_Record'Class)
   is
      use type Node_List.Glist;

      Win : constant File_Selector_Window_Access :=
        File_Selector_Window_Access (Get_Toplevel (Object));

   begin
      Show_Parent (Win.Explorer_Tree);
      Change_Directory (Win, Get_Selection (Win.Explorer_Tree));

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Up_Button_Clicked;

   -------------------------------
   -- On_Refresh_Button_Clicked --
   -------------------------------

   procedure On_Refresh_Button_Clicked
     (Object : access Gtk_Widget_Record'Class)
   is
      use type Node_List.Glist;

      Win : constant File_Selector_Window_Access :=
        File_Selector_Window_Access (Get_Toplevel (Object));

   begin
      Refresh_Files (Win);

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Refresh_Button_Clicked;

   -------------------------------
   -- On_Forward_Button_Clicked --
   -------------------------------

   procedure On_Forward_Button_Clicked
     (Object : access Gtk_Widget_Record'Class)
   is
      Win : constant File_Selector_Window_Access :=
        File_Selector_Window_Access (Get_Toplevel (Object));
      S   : String_Access;

   begin
      Pop (Win.Future_History, S);

      if Is_Empty (Win.Future_History) then
         Set_Sensitive (Win.Forward_Button, False);
      end if;

      if Is_Empty (Win.Past_History) then
         Set_Sensitive (Win.Back_Button, True);
      end if;

      Push (Win.Past_History,
            new String'(Locale_From_UTF8
                          (Get_Text (Win.Location_Combo_Entry))));

      Set_Text (Win.Location_Combo_Entry, Locale_To_UTF8 (S.all));
      Win.Moving_Through_History := True;
      Show_Directory (Win.Explorer_Tree, S.all);

      Free (S);

   exception
      when Stack_Empty =>
         null;

      when E : others =>
         Free (S);
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Forward_Button_Clicked;

   ------------------------
   -- Directory_Selected --
   ------------------------

   procedure Directory_Selected
     (Object : access Gtk_Widget_Record'Class)
   is
      Win : constant File_Selector_Window_Access :=
        File_Selector_Window_Access (Get_Toplevel (Object));
   begin
      Change_Directory
        (Win, Locale_From_UTF8
           (Get_Text (Win.Location_Combo_Entry)));
   end Directory_Selected;

   ---------------------
   -- Filter_Selected --
   ---------------------

   procedure Filter_Selected
     (Object : access Gtk_Widget_Record'Class)
   is
      Win : constant File_Selector_Window_Access :=
        File_Selector_Window_Access (Get_Toplevel (Object));
   begin
      Refresh_Files (Win);
   end Filter_Selected;

   --------------------------------------
   -- On_Location_Combo_Entry_Activate --
   --------------------------------------

   procedure On_Location_Combo_Entry_Activate
     (Object : access Gtk_Widget_Record'Class)
   is
      Win : constant File_Selector_Window_Access :=
        File_Selector_Window_Access (Get_Toplevel (Object));
      S   : constant String := Locale_From_UTF8
        (Get_Text (Win.Location_Combo_Entry));
   begin
      if Is_Directory (S) then
         Change_Directory (Win, S);
      end if;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Location_Combo_Entry_Activate;

   ---------------------------------
   -- On_Explorer_Tree_Select_Row --
   ---------------------------------

   procedure On_Explorer_Tree_Select_Row
     (Object : access Gtk_Widget_Record'Class)
   is
      Win : constant File_Selector_Window_Access :=
        File_Selector_Window_Access (Get_Toplevel (Object));

   begin
      Change_Directory (Win, Get_Selection (Dir_Tree (Object)));

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Explorer_Tree_Select_Row;

   --------------------------------
   -- On_File_List_End_Selection --
   --------------------------------

   procedure On_File_List_End_Selection
     (Object : access Gtk_Widget_Record'Class;
      Args   : Gtk_Args)
   is
      Win      : constant File_Selector_Window_Access :=
        File_Selector_Window_Access (Get_Toplevel (Object));
      Row_List : constant Gtk.Enums.Gint_List.Glist :=
        Get_Selection (Win.File_List);
      Event    : constant Gdk_Event := To_Event (Args, 3);

   begin
      if Gtk.Enums.Gint_List.Length (Row_List) /= 0 then
         Set_Text
           (Win.Selection_Entry,
            Get_Text
              (Win.File_List,
               Gtk.Enums.Gint_List.Get_Data (Row_List), 1));

         if Event /= null
           and then Get_Event_Type (Event) = Gdk_2button_Press
           and then Win.Own_Main_Loop
         then
            Main_Quit;
            Win.Own_Main_Loop := False;
         end if;
      end if;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_File_List_End_Selection;

   --------------------------------
   -- On_Selection_Entry_Changed --
   --------------------------------

   procedure On_Selection_Entry_Changed
     (Object : access Gtk_Widget_Record'Class)
   is
      pragma Unreferenced (Object);
   begin
      null;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Selection_Entry_Changed;

   --------------------------
   -- On_Ok_Button_Clicked --
   --------------------------

   procedure On_Ok_Button_Clicked
     (Object : access Gtk_Widget_Record'Class)
   is
      Win : constant File_Selector_Window_Access :=
        File_Selector_Window_Access (Object);
   begin
      Main_Quit;
      Win.Own_Main_Loop := False;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Ok_Button_Clicked;

   ------------------------------
   -- On_Cancel_Button_Clicked --
   ------------------------------

   procedure On_Cancel_Button_Clicked
     (Object : access Gtk_Widget_Record'Class)
   is
      Win : constant File_Selector_Window_Access :=
        File_Selector_Window_Access (Object);
   begin
      if Win /= null
        and then Win.Selection_Entry /= null
      then
         Set_Text (Win.Selection_Entry, "");
      end if;

      Main_Quit;
      Win.Own_Main_Loop := False;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Cancel_Button_Clicked;

   ----------------
   -- On_Destroy --
   ----------------

   procedure On_Destroy
     (Object : access Gtk_Widget_Record'Class)
   is
      Win : constant File_Selector_Window_Access :=
        File_Selector_Window_Access (Get_Toplevel (Object));
   begin
      Free (Win.Current_Directory);
      Free (Win.Current_Directory_Id);
      Free (Win.Files);
      Free (Win.Filters);

      if Win.Display_Idle_Handler /= 0 then
         Idle_Remove (Win.Display_Idle_Handler);
         Win.Display_Idle_Handler := 0;
      end if;

      if Win.Read_Idle_Handler /= 0 then
         Idle_Remove (Win.Read_Idle_Handler);
         Win.Read_Idle_Handler := 0;
      end if;

      if Win.Own_Main_Loop then
         Main_Quit;
         Win.Own_Main_Loop := False;
      end if;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Destroy;

   ----------------------------------
   -- On_File_List_Key_Press_Event --
   ----------------------------------

   function On_File_List_Key_Press_Event
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args) return Boolean
   is
      Win   : constant File_Selector_Window_Access :=
        File_Selector_Window_Access (Get_Toplevel (Object));
      Event : constant Gdk_Event := To_Event (Params, 1);

   begin
      declare
         S     : constant String := Locale_From_UTF8 (Get_String (Event));
         Found : Boolean := False;
      begin
         if S'Length /= 0
           and then (Is_Alphanumeric (S (S'First))
                     or else Is_Special (S (S'First)))
         then
            for J in 0 .. Get_Rows (Win.File_List) - 1 loop
               exit when Found;

               declare
                  T : constant String :=
                    Locale_From_UTF8 (Get_Text (Win.File_List, J, 1));
               begin
                  if T'Length /= 0
                    and then T (T'First) = S (S'First)
                  then
                     Found := True;
                     Select_Row (Win.File_List, J, 1);
                     Moveto (Win.File_List, J, 1, 0.1, 0.1);
                  end if;
               end;
            end loop;

            return True;
         else
            return False;
         end if;
      end;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
         return False;
   end On_File_List_Key_Press_Event;

   ---------------------------------------
   -- On_Location_Entry_Key_Press_Event --
   ---------------------------------------

   function On_Location_Entry_Key_Press_Event
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args) return Boolean
   is
      Win   : constant File_Selector_Window_Access :=
        File_Selector_Window_Access (Get_Toplevel (Object));
      Event : constant Gdk_Event := To_Event (Params, 1);

      use Gdk.Types;
   begin
      if Get_Key_Val (Event) = GDK_Return then
         declare
            S : constant String := Locale_From_UTF8
              (Get_Text (Win.Location_Combo_Entry));
         begin
            if Is_Directory (S) then
               Change_Directory (Win, S);
            end if;
         end;

         return True;
      end if;

      return False;
   end On_Location_Entry_Key_Press_Event;

   ----------------------------------------
   -- On_Selection_Entry_Key_Press_Event --
   ----------------------------------------

   function On_Selection_Entry_Key_Press_Event
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args) return Boolean
   is
      Win             : constant File_Selector_Window_Access :=
        File_Selector_Window_Access (Get_Toplevel (Object));

      Found           : Boolean := False;
      Event           : constant Gdk_Event := To_Event (Params, 1);
      S               : constant String :=
        Locale_From_UTF8 (Get_Text (Win.Selection_Entry));
      G               : constant String :=
        Locale_From_UTF8 (Get_String (Event));

      First_Match     : Gint := -1;
      --  The first column that completely matches S.

      Suffix_Length   : Integer := -1;
      --  The length of the biggest common matching prefix.

      Last            : Natural := S'Last;
      D               : Dir_Type;
      Best_Match      : String (1 .. 1024);
      File            : String (1 .. 1024);

      procedure Matcher
        (Base     : String;
         T        : String;
         Position : Gint := -1);
      --  ??? Should replace Matcher by
      --  Project_Explorers_Files.Greatest_Common_Path

      -------------
      -- Matcher --
      -------------

      procedure Matcher
        (Base     : String;
         T        : String;
         Position : Gint := -1)
      is
         K : Natural := 0;
      begin
         while K < T'Length
           and then K < Base'Length
           and then T (T'First + K) = Base (Base'First + K)
         loop
            K := K + 1;
         end loop;

         --  Does the prefix match S ?

         if K = Base'Length then
            if Suffix_Length = -1 then
               First_Match := Position;
               Best_Match (1 .. T'Length) := T;
               Suffix_Length := T'Length;

            else
               --  If there is already a biggest match, try to
               --  get it.

               while K < Suffix_Length
                 and then K < T'Length
                 and then T (T'First + K) = Best_Match (K + 1)
               loop
                  K := K + 1;
               end loop;

               Suffix_Length := K;
            end if;
         end if;
      end Matcher;

      use Gdk.Types;

   begin
      if Get_Key_Val (Event) = GDK_Tab then
         declare
            Dir  : constant String := Dir_Name (S);
            Base : constant String := Base_Name (S);
         begin
            --  Handle "Tab completion".
            --  The current implementation will fail if there are file names
            --  longer than 1024 characters.

            --  Handle the easy part: change to the longest directory available

            if Is_Absolute_Path (Dir) and then Is_Directory (Dir) then
               Change_Directory (Win, Dir);
            elsif Is_Directory (Win.Current_Directory.all & Dir) then
               Change_Directory (Win, Win.Current_Directory.all & Dir);
            else
               --  Dir is a non-existing directory: exit now

               return True;
            end if;

            --  Simple case: Base is a complete valid directory.

            if Is_Directory (Win.Current_Directory.all & Base) then
               Change_Directory (Win, Win.Current_Directory.all & Base);
               return True;
            end if;

            --  Base may be the start of a longer name: start the match and
            --  find out whether Base is the start of a unique directory, in
            --  which case open it, or the starat of a file.

            if Win.File_List /= null then
               for J in 0 .. Get_Rows (Win.File_List) - 1 loop
                  Matcher (Base,
                           Locale_From_UTF8 (Get_Text (Win.File_List, J, 1)),
                           J);
               end loop;
            end if;

            Open (D, Win.Current_Directory.all);

            loop
               Read (D, File, Last);
               exit when Last = 0;

               Matcher (Base, File (1 .. Last));
            end loop;

            Close (D);

            if First_Match /= -1 then
               --  The best match is a file.

               if Suffix_Length > 0 then
                  Select_Row (Win.File_List, First_Match, 1);
                  Moveto (Win.File_List, First_Match, 1, 0.0, 0.0);
                  Set_Text (Win.Selection_Entry,
                            Locale_To_UTF8 (Best_Match (1 .. Suffix_Length)));
                  Set_Position (Win.Selection_Entry, Gint (Suffix_Length));
               end if;

            else
               --  The best match is a directory.

               if Suffix_Length > 0 then
                  Set_Text (Win.Selection_Entry,
                            Locale_To_UTF8 (Best_Match (1 .. Suffix_Length)));
                  Set_Position (Win.Selection_Entry, Gint (Suffix_Length));
               end if;

               if Is_Directory (Win.Current_Directory.all
                                  & Best_Match (1 .. Suffix_Length))
                 and then Win.Current_Directory.all
                   /= Normalize_Pathname (Win.Current_Directory.all
                                            & Best_Match (1 .. Suffix_Length))
               then
                  Set_Text (Win.Selection_Entry, "");
                  Change_Directory (Win,
                                    Win.Current_Directory.all
                                      & Best_Match (1 .. Suffix_Length));
               end if;
            end if;

            return True;
         end;
      end if;

      if Win.File_List /= null then
         for J in 0 .. Get_Rows (Win.File_List) - 1 loop
            exit when Found;

            declare
               T : constant String :=
                 Locale_From_UTF8 (Get_Text (Win.File_List, J, 1));
               S : constant String :=
                 Locale_From_UTF8 (Get_Text (Win.Selection_Entry)) & G;
            begin
               if T'Length >= S'Length
                 and then T (T'First .. T'First + S'Length - 1)
                 = S (S'First .. S'First + S'Length - 1)
               then
                  Found := True;
                  Moveto (Win.File_List, J, 1, 0.0, 0.0);
               end if;
            end;
         end loop;
      end if;

      return False;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
         return False;
   end On_Selection_Entry_Key_Press_Event;

   -------------
   -- Gtk_New --
   -------------

   procedure Gtk_New
     (File_Selector_Window : out File_Selector_Window_Access;
      Root                 : String;
      Initial_Directory    : String;
      Dialog_Title         : String;
      Show_Files           : Boolean := True;
      History              : Histories.History) is
   begin
      File_Selector_Window := new File_Selector_Window_Record;

      if Is_Absolute_Path (Root)
        and then Root (Root'Last) = Directory_Separator
      then
         Initialize
           (File_Selector_Window, Root,
            Initial_Directory, Dialog_Title, Show_Files, History);
      else
         Initialize
           (File_Selector_Window, Get_Current_Dir,
            Initial_Directory, Dialog_Title, Show_Files, History);
      end if;
   end Gtk_New;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize
     (File_Selector_Window : access File_Selector_Window_Record'Class;
      Root                 : String;
      Initial_Directory    : String;
      Dialog_Title         : String;
      Show_Files           : Boolean := True;
      History              : Histories.History)
   is
      pragma Suppress (All_Checks);

      Toolbar1    : Gtk_Toolbar;

      Label1      : Gtk_Label;

      Hpaned1     : Gtk_Hpaned;

      Hbox1       : Gtk_Hbox;
      Hbox2       : Gtk_Hbox;
      Hbox3       : Gtk_Hbox;
      Hbox4       : Gtk_Hbox;
      Hbox5       : Gtk_Hbox;
      Hbox6       : Gtk_Hbox;
      Hbox7       : Gtk_Hbox;

      Hbuttonbox1 : Gtk_Hbutton_Box;

      Style       : Gtk_Style;

   begin
      Gtk.Window.Initialize (File_Selector_Window, Window_Toplevel);
      File_Selector_Window.History := History;

      Style := Get_Style (File_Selector_Window);
      File_Selector_Window.Highlighted_Style := Copy (Style);
      File_Selector_Window.Insensitive_Style := Copy (Style);
      File_Selector_Window.Normal_Style      := Copy (Style);

      Set_Foreground
        (File_Selector_Window.Insensitive_Style,
         State_Normal,
         Gdk_Color'(Get_Foreground (Style, State_Insensitive)));

      File_Selector_Window.Home_Directory := new String'(Root);

      Gtk_New
        (File_Selector_Window.Explorer_Tree,
         File_Selector_Window.Home_Directory.all);

      --  Set_Indent (File_Selector_Window.Explorer_Tree, 10);
      --  Set_Row_Height (File_Selector_Window.Explorer_Tree, 15);

      Set_Title (File_Selector_Window, Dialog_Title);

      if Show_Files then
         Set_Default_Size (File_Selector_Window, 600, 500);
      else
         Set_Default_Size (File_Selector_Window, 400, 647);
      end if;

      Set_Policy (File_Selector_Window, False, True, False);
      Set_Position (File_Selector_Window, Win_Pos_Center);
      Set_Modal (File_Selector_Window, False);

      Gtk_New_Vbox (File_Selector_Window.File_Selector_Vbox, False, 0);
      Add (File_Selector_Window, File_Selector_Window.File_Selector_Vbox);

      Gtk_New_Hbox (Hbox1, False, 0);
      Pack_Start (File_Selector_Window.File_Selector_Vbox,
                  Hbox1, False, False, 3);

      Gtk_New_Hbox (Hbox3, False, 0);
      Pack_Start (Hbox1, Hbox3, True, True, 0);

      Gtk_New
        (Toolbar1,
         Orientation_Horizontal, Toolbar_Both);

      Set_Icon_Size (Toolbar1, Icon_Size_Button);
      Set_Style (Toolbar1,  Toolbar_Icons);
      File_Selector_Window.Back_Button := Insert_Stock
        (Toolbar1,
         Stock_Go_Back,
         -"Go To Previous Location",
         Position => -1);
      Set_Sensitive (File_Selector_Window.Back_Button, False);
      Widget_Callback.Connect
        (File_Selector_Window.Back_Button, "clicked",
         Widget_Callback.To_Marshaller (On_Back_Button_Clicked'Access));

      File_Selector_Window.Forward_Button := Insert_Stock
        (Toolbar1,
         Stock_Go_Forward,
         -"Go To Next Location",
         Position => -1);
      Set_Sensitive (File_Selector_Window.Forward_Button, False);
      Widget_Callback.Connect
        (File_Selector_Window.Forward_Button, "clicked",
         Widget_Callback.To_Marshaller (On_Forward_Button_Clicked'Access));

      Gtk_New (File_Selector_Window.Up_Icon, Stock_Go_Up, Icon_Size_Button);
      File_Selector_Window.Up_Button := Append_Element
        (Toolbar => Toolbar1,
         The_Type => Toolbar_Child_Button,
         Tooltip_Text => -"Go To Parent Directory",
         Icon => Gtk_Widget (File_Selector_Window.Up_Icon));

      Widget_Callback.Connect
        (File_Selector_Window.Up_Button, "clicked",
         Widget_Callback.To_Marshaller (On_Up_Button_Clicked'Access));

      Gtk_New
        (File_Selector_Window.Refresh_Icon, Stock_Refresh, Icon_Size_Button);
      File_Selector_Window.Refresh_Button := Append_Element
        (Toolbar => Toolbar1,
         The_Type => Toolbar_Child_Button,
         Tooltip_Text => -"Refresh",
         Icon => Gtk_Widget (File_Selector_Window.Refresh_Icon));
      Widget_Callback.Connect
        (File_Selector_Window.Refresh_Button, "clicked",
         Widget_Callback.To_Marshaller (On_Refresh_Button_Clicked'Access));

      File_Selector_Window.Home_Button := Insert_Stock
        (Toolbar1,
         Stock_Home,
         -"Go To Home Directory",
         Position => -1);
      Set_Sensitive (File_Selector_Window.Home_Button, True);
      Widget_Callback.Connect
        (File_Selector_Window.Home_Button, "clicked",
         Widget_Callback.To_Marshaller (On_Home_Button_Clicked'Access));

      Pack_Start (Hbox3, Toolbar1, True, True, 3);

      Gtk_New_Hbox (Hbox2, False, 0);
      Pack_Start
        (File_Selector_Window.File_Selector_Vbox,
         Hbox2, False, False, 3);

      Gtk_New (Label1, -("Exploring :"));
      Pack_Start (Hbox2, Label1, False, False, 3);

      Gtk_New (File_Selector_Window.Location_Combo);
      Set_Case_Sensitive (File_Selector_Window.Location_Combo, True);
      Pack_Start (Hbox2,
                  File_Selector_Window.Location_Combo, True, True, 3);
      Widget_Callback.Object_Connect
        (Get_Popup_Window (File_Selector_Window.Location_Combo),
         "hide",
         Widget_Callback.To_Marshaller (Directory_Selected'Access),
         File_Selector_Window.Location_Combo);

      if History /= null then
         Get_History (History.all, Directories_Hist_Key,
                      File_Selector_Window.Location_Combo);
      end if;

      File_Selector_Window.Location_Combo_Entry :=
        Get_Entry (File_Selector_Window.Location_Combo);
      Set_Editable (File_Selector_Window.Location_Combo_Entry, True);
      Set_Max_Length (File_Selector_Window.Location_Combo_Entry, 0);
      Set_Visibility (File_Selector_Window.Location_Combo_Entry, True);
      Widget_Callback.Connect
        (File_Selector_Window.Location_Combo_Entry, "activate",
         Widget_Callback.To_Marshaller
         (On_Location_Combo_Entry_Activate'Access));
      Return_Callback.Connect
        (File_Selector_Window.Location_Combo_Entry,
         "key_press_event", On_Location_Entry_Key_Press_Event'Access,
          After => False);

      Gtk_New_Hpaned (Hpaned1);
      Set_Position (Hpaned1, 200);
      Set_Handle_Size (Hpaned1, 10);
      Set_Gutter_Size (Hpaned1, 6);

      Gtk_New_Hbox (Hbox7, False, 0);
      Pack_Start
        (File_Selector_Window.File_Selector_Vbox,
         Hbox7, True, True, 3);

      Pack_Start (Hbox7, Hpaned1, True, True, 3);

      Gtk_New (File_Selector_Window.Explorer_Tree_Scrolledwindow);
      Set_Policy
        (File_Selector_Window.Explorer_Tree_Scrolledwindow,
         Policy_Automatic, Policy_Always);

      Add (Hpaned1, File_Selector_Window.Explorer_Tree_Scrolledwindow);

      Set_Column_Width (File_Selector_Window.Explorer_Tree, 0, 80);
      Set_Column_Width (File_Selector_Window.Explorer_Tree, 1, 80);
      Set_Column_Width (File_Selector_Window.Explorer_Tree, 2, 80);
      Widget_Callback.Connect
        (File_Selector_Window.Explorer_Tree, "tree_select_row",
         Widget_Callback.To_Marshaller (On_Explorer_Tree_Select_Row'Access));
      Add (File_Selector_Window.Explorer_Tree_Scrolledwindow,
           File_Selector_Window.Explorer_Tree);

      if Show_Files then
         Gtk_New (File_Selector_Window.Files_Scrolledwindow);
         Set_Policy
           (File_Selector_Window.Files_Scrolledwindow,
            Policy_Automatic, Policy_Always);
         Add (Hpaned1, File_Selector_Window.Files_Scrolledwindow);

         Gtk_New (File_Selector_Window.File_List, 3);
         Set_Selection_Mode (File_Selector_Window.File_List, Selection_Single);
         Set_Shadow_Type (File_Selector_Window.File_List, Shadow_In);
         Set_Show_Titles (File_Selector_Window.File_List, True);
         Set_Column_Width (File_Selector_Window.File_List, 0, 20);
         Set_Column_Width (File_Selector_Window.File_List, 1, 180);
         Set_Column_Width (File_Selector_Window.File_List, 2, 80);
         --  Set_Row_Height (File_Selector_Window.File_List, 15);

         Return_Callback.Connect
           (File_Selector_Window.File_List, "key_press_event",
            On_File_List_Key_Press_Event'Access);

         Widget_Callback.Connect
           (File_Selector_Window.File_List, "select_row",
            On_File_List_End_Selection'Access);
         Add (File_Selector_Window.Files_Scrolledwindow,
              File_Selector_Window.File_List);

         Gtk_New (File_Selector_Window.File_Icon_Label, -(""));
         Set_Column_Widget
           (File_Selector_Window.File_List, 0,
            File_Selector_Window.File_Icon_Label);

         Gtk_New (File_Selector_Window.File_Name_Label, -("Name"));
         Set_Justify (File_Selector_Window.File_Name_Label, Justify_Left);
         Set_Column_Widget
           (File_Selector_Window.File_List, 1,
            File_Selector_Window.File_Name_Label);

         Gtk_New (File_Selector_Window.File_Text_Label, -("Info"));
         Set_Justify (File_Selector_Window.File_Text_Label, Justify_Left);
         Set_Column_Widget
           (File_Selector_Window.File_List, 2,
            File_Selector_Window.File_Text_Label);
      end if;

      Gtk_New_Hbox (Hbox4, False, 0);
      Pack_Start
        (File_Selector_Window.File_Selector_Vbox,
         Hbox4, False, False, 3);

      Gtk_New (File_Selector_Window.Filter_Combo);
      Set_Case_Sensitive (File_Selector_Window.Filter_Combo, False);

      Widget_Callback.Object_Connect
        (Get_Popup_Window (File_Selector_Window.Filter_Combo),
         "hide",
         Widget_Callback.To_Marshaller (Filter_Selected'Access),
         File_Selector_Window.Filter_Combo);

      Pack_Start (Hbox4,
                  File_Selector_Window.Filter_Combo, True, True, 3);

      File_Selector_Window.Filter_Combo_Entry :=
        Get_Entry (File_Selector_Window.Filter_Combo);
      Set_Editable (File_Selector_Window.Filter_Combo_Entry, False);
      Set_Max_Length (File_Selector_Window.Filter_Combo_Entry, 0);
      Set_Visibility (File_Selector_Window.Filter_Combo_Entry, True);

      Gtk_New_Hbox (Hbox5, False, 0);
      Pack_Start
        (File_Selector_Window.File_Selector_Vbox,
         Hbox5, False, False, 3);

      Gtk_New (File_Selector_Window.Selection_Entry);
      Set_Editable (File_Selector_Window.Selection_Entry, True);
      Set_Max_Length (File_Selector_Window.Selection_Entry, 0);
      Set_Visibility (File_Selector_Window.Selection_Entry, True);
      Pack_Start
        (Hbox5, File_Selector_Window.Selection_Entry, True, True, 3);
      Set_Activates_Default (File_Selector_Window.Selection_Entry, True);

      Return_Callback.Connect
        (File_Selector_Window.Selection_Entry,
         "key_press_event", On_Selection_Entry_Key_Press_Event'Access);

      Widget_Callback.Connect
        (File_Selector_Window.Selection_Entry, "changed",
         Widget_Callback.To_Marshaller (On_Selection_Entry_Changed'Access));

      Gtk_New_Hbox (Hbox6, False, 0);
      Pack_Start
        (File_Selector_Window.File_Selector_Vbox,
         Hbox6, False, False, 3);

      Gtk_New (Hbuttonbox1);
      Set_Spacing (Hbuttonbox1, 30);
      Set_Layout (Hbuttonbox1, Buttonbox_Spread);
      Set_Child_Size (Hbuttonbox1, 85, 27);
      Set_Child_Ipadding (Hbuttonbox1, 7, 0);
      Add (Hbox6, Hbuttonbox1);

      Gtk_New_From_Stock (File_Selector_Window.Ok_Button, Stock_Ok);
      Set_Relief (File_Selector_Window.Ok_Button, Relief_Normal);
      Set_Flags (File_Selector_Window.Ok_Button, Can_Default);
      Add (Hbuttonbox1, File_Selector_Window.Ok_Button);

      Gtk_New_From_Stock (File_Selector_Window.Cancel_Button, Stock_Cancel);
      Set_Relief (File_Selector_Window.Cancel_Button, Relief_Normal);
      Set_Flags (File_Selector_Window.Cancel_Button, Can_Default);
      Add (Hbuttonbox1, File_Selector_Window.Cancel_Button);

      Widget_Callback.Connect
        (File_Selector_Window, "realize",
         Widget_Callback.To_Marshaller (Realized'Access));

      Realize (File_Selector_Window);

      if Initial_Directory /= "" then
         Show_Directory
           (File_Selector_Window.Explorer_Tree,
            Initial_Directory,
            Get_Window (File_Selector_Window));
      else
         Show_Directory
           (File_Selector_Window.Explorer_Tree,
            Get_Current_Dir,
            Get_Window (File_Selector_Window));
      end if;

      Widget_Callback.Connect
        (File_Selector_Window, "destroy",
         Widget_Callback.To_Marshaller (On_Destroy'Access));

      Grab_Default (File_Selector_Window.Ok_Button);
      Grab_Focus (File_Selector_Window.Selection_Entry);
   end Initialize;

   -------------
   -- Destroy --
   -------------

   procedure Destroy (Filter : access File_Filter_Record) is
   begin
      Free (Filter.Label);
   end Destroy;

   ----------
   -- Free --
   ----------

   procedure Free (S : in out String) is
      pragma Unreferenced (S);
   begin
      null;
   end Free;

   ----------
   -- Free --
   ----------

   procedure Free (Filter : in out File_Filter) is
      procedure Unchecked_Free is new Unchecked_Deallocation
        (File_Filter_Record'Class, File_Filter);
   begin
      Destroy (Filter);
      Unchecked_Free (Filter);
   end Free;

   ---------------------
   -- Browse_Location --
   ---------------------

   procedure Browse_Location (Ent : access Gtk_Widget_Record'Class) is
      Result : constant Gtk_Entry := Gtk_Entry (Ent);
      Name   : constant String := Select_Directory
        (-"Select directory",
         Base_Directory =>
           Dir_Name (Normalize_Pathname
                       (Locale_From_UTF8 (Get_Text (Result)),
                        Resolve_Links => False)));
   begin
      if Name /= "" then
         Set_Text (Result, Locale_To_UTF8 (Name));
      end if;
   end Browse_Location;

end Gtkada.File_Selector;
