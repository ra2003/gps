-----------------------------------------------------------------------
--                   GVD - The GNU Visual Debugger                   --
--                                                                   --
--                      Copyright (C) 2000-2002                      --
--                             ACT-Europe                            --
--                                                                   --
-- GVD is free  software;  you can redistribute it and/or modify  it --
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

with Gdk.Color;                use Gdk.Color;
with Gdk.Cursor;               use Gdk.Cursor;
with Gdk.Drawable;             use Gdk.Drawable;
with Gdk.Event;                use Gdk.Event;
with Gdk.GC;                   use Gdk.GC;
with Gdk.Main;                 use Gdk.Main;
with Gdk.Pixmap;               use Gdk.Pixmap;
with Gdk.Window;               use Gdk.Window;
with Glib.Convert;             use Glib.Convert;
with Glib.Object;              use Glib.Object;
with Glib.Values;              use Glib.Values;
with Glib;                     use Glib;
with Gtk.Cell_Renderer_Toggle; use Gtk.Cell_Renderer_Toggle;
with Gtk.Clist;                use Gtk.Clist;
with Gtk.Combo;                use Gtk.Combo;
with Gtk.Container;            use Gtk.Container;
with Gtk.GEntry;               use Gtk.GEntry;
with Gtk.Handlers;
with Gtk.Handlers;             use Gtk.Handlers;
with Gtk.Item;                 use Gtk.Item;
with Gtk.Label;                use Gtk.Label;
with Gtk.List;                 use Gtk.List;
with Gtk.List_Item;            use Gtk.List_Item;
with Gtk.Menu;                 use Gtk.Menu;
with Gtk.Menu_Item;            use Gtk.Menu_Item;
with Gtk.Tree_Model;           use Gtk.Tree_Model;
with Gtk.Tree_Store;           use Gtk.Tree_Store;
with Gtk.Tree_View;            use Gtk.Tree_View;
with Gtk.Tree_View_Column;     use Gtk.Tree_View_Column;
with Gtk.Tree_Selection;       use Gtk.Tree_Selection;
with Gtk.Widget;               use Gtk.Widget;
with Pango.Enums;              use Pango.Enums;
with Pango.Font;               use Pango.Font;
with Pango.Layout;             use Pango.Layout;

package body GUI_Utils is

   type Contextual_Menu_Data is record
      Create  : Contextual_Menu_Create;
      Destroy : Contextual_Menu_Destroy;
      Widget  : Gtk_Widget;
   end record;

   package Contextual_Callback is new Gtk.Handlers.User_Return_Callback
     (Gtk_Widget_Record, Boolean, Contextual_Menu_Data);

   function Button_Press_For_Contextual_Menu
     (Widget : access Gtk_Widget_Record'Class;
      Event  : Gdk.Event.Gdk_Event;
      Data   : Contextual_Menu_Data) return Boolean;
   --  Callback that pops up the contextual menu if needed

   function Unmap_Menu
     (Menu : access Gtk_Widget_Record'Class;
      Data : Contextual_Menu_Data) return Boolean;

   procedure Radio_Callback
     (Model  : access GObject_Record'Class;
      Params : Glib.Values.GValues;
      Data   : Glib.Gint);
   --  Callback for the toggle renderer

   procedure Edited_Callback
     (Model  : access GObject_Record'Class;
      Params : Glib.Values.GValues;
      Data   : Glib.Gint);
   --  Callback for the editable renderer

   function Add_Unique_List_Entry
     (List    : access Gtk.List.Gtk_List_Record'Class;
      Text    : String;
      Prepend : Boolean := False) return Gtk_List_Item;
   --  Internal version of Add_Unique_List_Entry, that also returns the added
   --  item.

   ---------------------------
   -- Add_Unique_List_Entry --
   ---------------------------

   function Add_Unique_List_Entry
     (List    : access Gtk.List.Gtk_List_Record'Class;
      Text    : String;
      Prepend : Boolean := False) return Gtk_List_Item
   is
      use Widget_List;

      Item     : Gtk_List_Item;
      Children : Widget_List.Glist := Get_Children (List);

   begin
      --  Check whether Text is already in the list

      while Children /= Null_List loop
         Item := Gtk_List_Item (Get_Data (Children));

         if Get (Gtk_Label (Get_Child (Item))) = Text then
            return Item;
         end if;

         Children := Next (Children);
      end loop;

      --  Add the new item in the list

      Gtk_New (Item, Locale_To_UTF8 (Text));
      Show (Item);

      if Prepend then
         Append (Children, Gtk_Widget (Item));
         Prepend_Items (List, Children);
      else
         Add (List, Item);
      end if;

      return Item;
   end Add_Unique_List_Entry;

   ---------------------------
   -- Add_Unique_List_Entry --
   ---------------------------

   procedure Add_Unique_List_Entry
     (List : access Gtk.List.Gtk_List_Record'Class;
      Text : String;
      Prepend : Boolean := False)
   is
      Item : Gtk_List_Item;
      pragma Unreferenced (Item);
   begin
      Item := Add_Unique_List_Entry (List, Text, Prepend);
   end Add_Unique_List_Entry;

   ----------------------------
   -- Add_Unique_Combo_Entry --
   ----------------------------

   procedure Add_Unique_Combo_Entry
     (Combo           : access Gtk.Combo.Gtk_Combo_Record'Class;
      Text            : String;
      Item_String     : String  := "";
      Use_Item_String : Boolean := False;
      Prepend         : Boolean := False)
   is
      Item : Gtk_List_Item;
      pragma Unreferenced (Item);

   begin
      Item := Add_Unique_Combo_Entry
        (Combo, Text, Item_String, Use_Item_String, Prepend);
   end Add_Unique_Combo_Entry;

   ----------------------------
   -- Add_Unique_Combo_Entry --
   ----------------------------

   function Add_Unique_Combo_Entry
     (Combo       : access Gtk.Combo.Gtk_Combo_Record'Class;
      Text        : String;
      Item_String : String := "";
      Use_Item_String : Boolean := False;
      Prepend     : Boolean := False) return Gtk.List_Item.Gtk_List_Item
   is
      Item : Gtk_List_Item;
   begin
      Item := Add_Unique_List_Entry (Get_List (Combo), Text, Prepend);

      if Use_Item_String then
         Set_Item_String (Combo, Gtk_Item (Item), Item_String);
      end if;
      return Item;
   end Add_Unique_Combo_Entry;

   -----------------------
   -- Get_Index_In_List --
   -----------------------

   function Get_Index_In_List
     (Combo : access Gtk.Combo.Gtk_Combo_Record'Class) return Integer
   is
      use type Widget_List.Glist;
      Entry_Text : constant String := Get_Text (Get_Entry (Combo));
      Children  : Widget_List.Glist := Get_Children (Get_List (Combo));
      Item      : Gtk_List_Item;
      Label     : Gtk_Label;
      Index     : Integer := -1;
   begin
      --  We have to search explicitely in the list, since the selection might
      --  be different from what is actually displayed in the list, for
      --  instance if the text in the entry was modified programmatically.

      while Children /= Widget_List.Null_List loop
         Item := Gtk_List_Item (Widget_List.Get_Data (Children));
         Label := Gtk_Label (Get_Child (Item));
         Index := Index + 1;

         if Get_Text (Label) = Entry_Text then
            return Index;
         end if;

         Children := Widget_List.Next (Children);
      end loop;

      return -1;
   end Get_Index_In_List;

   ----------------------------
   -- Propagate_Expose_Event --
   ----------------------------

   procedure Propagate_Expose_Event
     (Container : access Gtk.Container.Gtk_Container_Record'Class;
      Event     : Gdk.Event.Gdk_Event_Expose)
   is
      use Widget_List;
      Children, Tmp : Widget_List.Glist;
   begin
      Children := Get_Children (Container);
      Tmp := Children;
      while Tmp /= Null_List loop
         Propagate_Expose (Container, Get_Data (Tmp), Event);
         Tmp := Next (Tmp);
      end loop;

      Free (Children);
   end Propagate_Expose_Event;

   -----------------------------
   -- Find_First_Row_Matching --
   -----------------------------

   function Find_First_Row_Matching
     (Clist  : access Gtk.Clist.Gtk_Clist_Record'Class;
      Column : Gint;
      Text   : String) return Gint
   is
      Row : Gint := 0;
      Max : constant Gint := Get_Rows (Clist);
   begin
      while Row < Max loop
         if Get_Text (Clist, Row, Column) = Text then
            return Row;
         end if;
         Row := Row + 1;
      end loop;
      return -1;
   end Find_First_Row_Matching;

   ---------------------
   -- Set_Busy_Cursor --
   ---------------------

   procedure Set_Busy_Cursor
     (Window        : Gdk.Window.Gdk_Window;
      Busy          : Boolean := True;
      Force_Refresh : Boolean := False)
   is
      use type Gdk_Window;
      Cursor     : Gdk_Cursor;
   begin
      if Window /= null then
         if Busy then
            Gdk_New (Cursor, Watch);
            Set_Cursor (Window, Cursor);
            Destroy (Cursor);
         else
            Set_Cursor (Window, null);
         end if;

         if Force_Refresh then
            Gdk.Main.Flush;
         end if;
      end if;
   end Set_Busy_Cursor;

   ----------------
   -- Unmap_Menu --
   ----------------

   function Unmap_Menu
     (Menu : access Gtk_Widget_Record'Class;
      Data : Contextual_Menu_Data) return Boolean is
   begin
      if Data.Destroy /= null then
         Data.Destroy (Data.Widget, Gtk_Menu (Menu));
      end if;
      return False;
   end Unmap_Menu;

   --------------------------------------
   -- Button_Press_For_Contextual_Menu --
   --------------------------------------

   function Button_Press_For_Contextual_Menu
     (Widget : access Gtk_Widget_Record'Class;
      Event  : Gdk.Event.Gdk_Event;
      Data   : Contextual_Menu_Data) return Boolean
   is
      Menu : Gtk_Menu;
   begin
      if Get_Button (Event) = 3
        and then Get_Event_Type (Event) = Button_Press
      then
         Menu := Data.Create (Widget, Event);
         if Menu /= null then
            Contextual_Callback.Connect
              (Menu, "unmap_event",
               Contextual_Callback.To_Marshaller
               (Unmap_Menu'Unrestricted_Access), Data);

            Grab_Focus (Widget);
            Show_All (Menu);
            Popup (Menu,
                   Button        => Gdk.Event.Get_Button (Event),
                   Activate_Time => Gdk.Event.Get_Time (Event));
            Emit_Stop_By_Name (Widget, "button_press_event");
            return True;
         end if;
      end if;
      return False;
   end Button_Press_For_Contextual_Menu;

   ------------------------------
   -- Register_Contextual_Menu --
   ------------------------------

   procedure Register_Contextual_Menu
     (Widget       : access Gtk_Widget_Record'Class;
      Menu_Create  : Contextual_Menu_Create  := null;
      Menu_Destroy : Contextual_Menu_Destroy := null) is
   begin
      --  If the widget doesn't have a window, it might not work. But then, if
      --  the children have windows and do not handle the event, this might get
      --  propagated, and the contextual menu will be properly displayed.
      --  So we just avoid a gtk warning
      if not No_Window_Is_Set (Widget) then
         Add_Events (Widget, Button_Press_Mask or Button_Release_Mask);
      end if;

      Contextual_Callback.Connect
        (Widget, "button_press_event",
         Contextual_Callback.To_Marshaller
         (Button_Press_For_Contextual_Menu'Access),
         (Menu_Create, Menu_Destroy, Gtk_Widget (Widget)));
   end Register_Contextual_Menu;

   ---------------------------
   -- User_Contextual_Menus --
   ---------------------------

   package body User_Contextual_Menus is

      function Button_Press_For_Contextual_Menu
        (Widget : access Gtk_Widget_Record'Class;
         Event  : Gdk.Event.Gdk_Event;
         User   : Callback_User_Data) return Boolean;

      function Unmap_User_Menu
        (Menu : access Gtk_Widget_Record'Class;
         User : Callback_User_Data) return Boolean;

      ---------------------
      -- Unmap_User_Menu --
      ---------------------

      function Unmap_User_Menu
        (Menu : access Gtk_Widget_Record'Class;
         User : Callback_User_Data) return Boolean is
      begin
         if User.Menu_Destroy /= null then
            User.Menu_Destroy (User.User, Gtk_Menu (Menu));
         end if;
         return False;
      end Unmap_User_Menu;

      --------------------------------------
      -- Button_Press_For_Contextual_Menu --
      --------------------------------------

      function Button_Press_For_Contextual_Menu
        (Widget : access Gtk_Widget_Record'Class;
         Event  : Gdk.Event.Gdk_Event;
         User   : Callback_User_Data) return Boolean
      is
         Menu : Gtk_Menu;
      begin
         if Get_Button (Event) = 3
           and then Get_Event_Type (Event) = Button_Press
         then
            Menu := User.Menu_Create (User.User, Event);
            if Menu /= null then
               Contextual_Callback.Connect
                 (Menu, "unmap_event",
                  Contextual_Callback.To_Marshaller
                  (Unmap_User_Menu'Unrestricted_Access), User);

               Grab_Focus (Widget);
               Show_All (Menu);
               Popup (Menu,
                      Button        => Gdk.Event.Get_Button (Event),
                      Activate_Time => Gdk.Event.Get_Time (Event));
               Emit_Stop_By_Name (Widget, "button_press_event");
               return True;
            end if;
         end if;
         return False;
      end Button_Press_For_Contextual_Menu;

      ------------------------------
      -- Register_Contextual_Menu --
      ------------------------------

      procedure Register_Contextual_Menu
        (Widget       : access Gtk.Widget.Gtk_Widget_Record'Class;
         User         : User_Data;
         Menu_Create  : Contextual_Menu_Create := null;
         Menu_Destroy : Contextual_Menu_Destroy := null) is
      begin
         if not No_Window_Is_Set (Widget) then
            Add_Events (Widget, Button_Press_Mask or Button_Release_Mask);
         end if;
         Contextual_Callback.Connect
           (Widget, "button_press_event",
            Contextual_Callback.To_Marshaller
            (User_Contextual_Menus.Button_Press_For_Contextual_Menu'
              Unrestricted_Access),
            (Menu_Create  => Menu_Create,
             Menu_Destroy => Menu_Destroy,
             User         => User));
      end Register_Contextual_Menu;
   end User_Contextual_Menus;

   -------------------------
   -- Remove_All_Children --
   -------------------------

   procedure Remove_All_Children
     (Container : access Gtk.Container.Gtk_Container_Record'Class)
   is
      use Widget_List;
      Children : Widget_List.Glist := Get_Children (Container);
      N : Widget_List.Glist;
   begin
      while Children /= Null_List loop
         N := Children;
         Children := Next (Children);
         Remove (Container, Widget_List.Get_Data (N));
      end loop;
   end Remove_All_Children;

   ----------------------------
   -- Set_Radio_And_Callback --
   ----------------------------

   procedure Set_Radio_And_Callback
     (Model    : access Gtk.Tree_Store.Gtk_Tree_Store_Record'Class;
      Renderer : access Gtk_Cell_Renderer_Toggle_Record'Class;
      Column   : Glib.Gint) is
   begin
      Set_Radio (Renderer, True);

      Tree_Model_Callback.Object_Connect
        (Renderer, "toggled",
         Radio_Callback'Access, Slot_Object => Model, User_Data => Column);
   end Set_Radio_And_Callback;

   --------------------
   -- Radio_Callback --
   --------------------

   procedure Radio_Callback
     (Model  : access GObject_Record'Class;
      Params : Glib.Values.GValues;
      Data   : Glib.Gint)
   is
      M           : constant Gtk_Tree_Store := Gtk_Tree_Store (Model);
      Iter, Tmp   : Gtk_Tree_Iter;
      Path_String : constant String := Get_String (Nth (Params, 1));

   begin
      Iter := Get_Iter_From_String (M, Path_String);

      if Iter /= Null_Iter then
         --  Can't click on an already active item, for a radio renderer, since
         --  we want at least one selected item

         if not Get_Boolean (M, Iter, Data) then
            Tmp := Get_Iter_First (M);

            while Tmp /= Null_Iter loop
               Set (M, Tmp, Data, False);
               Next (M, Tmp);
            end loop;

            Set (M, Iter, Data, True);
         end if;
      end if;
   end Radio_Callback;

   -------------------------------
   -- Set_Editable_And_Callback --
   -------------------------------

   procedure Set_Editable_And_Callback
     (Model    : access Gtk.Tree_Store.Gtk_Tree_Store_Record'Class;
      Renderer : access Gtk_Cell_Renderer_Text_Record'Class;
      Column   : Glib.Gint) is
   begin
      Tree_Model_Callback.Object_Connect
        (Renderer, "edited", Edited_Callback'Access,
         Slot_Object => Model, User_Data => Column);
   end Set_Editable_And_Callback;

   ---------------------
   -- Edited_Callback --
   ---------------------

   procedure Edited_Callback
     (Model  : access GObject_Record'Class;
      Params : Glib.Values.GValues;
      Data   : Glib.Gint)
   is
      M             : constant Gtk_Tree_Store := Gtk_Tree_Store (Model);
      Iter          : Gtk_Tree_Iter;
      Path_String   : constant String := Get_String (Nth (Params, 1));
      Text_Value    : constant GValue := Nth (Params, 2);

   begin
      Iter := Get_Iter_From_String (M, Path_String);
      Set_Value (M, Iter, Data, Text_Value);
   end Edited_Callback;

   -----------------------------
   -- Create_Pixmap_From_Text --
   -----------------------------

   procedure Create_Pixmap_From_Text
     (Text     : String;
      Font     : Pango.Font.Pango_Font_Description;
      Bg_Color : Gdk.Color.Gdk_Color;
      Widget   : access Gtk_Widget_Record'Class;
      Pixmap   : out Gdk.Gdk_Pixmap;
      Width    : out Glib.Gint;
      Height   : out Glib.Gint;
      Wrap_Width : Glib.Gint := -1)
   is
      Margin : constant := 2;
      GC : Gdk_GC;
      Layout : Pango_Layout;
   begin
      Gdk_New (GC, Get_Window (Widget));
      Set_Foreground (GC, Bg_Color);

      Layout := Create_Pango_Layout (Widget, Text);
      Set_Font_Description (Layout, Font);

      if Wrap_Width /= -1 then
         Set_Wrap (Layout, Pango_Wrap_Char);
         Set_Width (Layout, Wrap_Width * Pango_Scale);
      end if;

      Get_Pixel_Size (Layout, Width, Height);
      Width := Width + Margin * 2;
      Height := Height + Margin * 2;

      Gdk.Pixmap.Gdk_New
        (Pixmap, Get_Window (Widget), Width, Height);
      Draw_Rectangle
        (Pixmap,
         GC,
         Filled => True,
         X      => 0,
         Y      => 0,
         Width  => Width - 1,
         Height => Height - 1);

      Set_Foreground (GC, Black (Get_Default_Colormap));
      Draw_Rectangle
        (Pixmap,
         GC,
         Filled => False,
         X      => 0,
         Y      => 0,
         Width  => Width - 1,
         Height => Height - 1);

      Draw_Layout (Pixmap, GC, Margin, Margin, Layout);

      Unref (Layout);
      Unref (GC);
   end Create_Pixmap_From_Text;

   -------------------------
   -- Full_Path_Menu_Item --
   -------------------------

   -------------
   -- Gtk_New --
   -------------

   procedure Gtk_New
     (Menu_Item : out Full_Path_Menu_Item;
      Label     : String := "";
      Path      : String := "") is
   begin
      Menu_Item := new Full_Path_Menu_Item_Record (Path'Length);
      Initialize (Menu_Item, Label, Path);
   end Gtk_New;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize
     (Menu_Item : access Full_Path_Menu_Item_Record'Class;
      Label     : String;
      Path      : String) is
   begin
      Initialize (Gtk_Menu_Item (Menu_Item), Locale_To_UTF8 (Label));
      Menu_Item.Full_Path := Path;
   end Initialize;

   --------------
   -- Get_Path --
   --------------

   function Get_Path
     (Menu_Item : access Full_Path_Menu_Item_Record) return String is
   begin
      return Menu_Item.Full_Path;
   end Get_Path;

   -------------------------
   -- Find_Iter_For_Event --
   -------------------------

   function Find_Iter_For_Event
     (Tree  : access Gtk_Tree_View_Record'Class;
      Model : access Gtk.Tree_Model.Gtk_Tree_Model_Record'Class;
      Event : Gdk_Event) return Gtk_Tree_Iter
   is
      X         : Gdouble;
      Y         : Gdouble;
      Buffer_X  : Gint;
      Buffer_Y  : Gint;
      Row_Found : Boolean;
      Path      : Gtk_Tree_Path;
      Column    : Gtk_Tree_View_Column := null;
      Iter      : Gtk_Tree_Iter := Null_Iter;
      N_Model   : Gtk_Tree_Model;
   begin
      if Event /= null then
         X := Get_X (Event);
         Y := Get_Y (Event);
         Path := Gtk_New;
         Get_Path_At_Pos
           (Tree,
            Gint (X),
            Gint (Y),
            Path,
            Column,
            Buffer_X,
            Buffer_Y,
            Row_Found);

         if Path = null then
            return Iter;
         end if;

         Iter := Get_Iter (Model, Path);
         Path_Free (Path);
      else
         Get_Selected (Get_Selection (Tree),
                       N_Model,
                       Iter);
      end if;

      return Iter;
   end Find_Iter_For_Event;

end GUI_Utils;
