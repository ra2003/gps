------------------------------------------------------------------------------
--                                  G P S                                   --
--                                                                          --
--                     Copyright (C) 2018-2019, AdaCore                     --
--                                                                          --
-- This is free software;  you can redistribute it  and/or modify it  under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  This software is distributed in the hope  that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General  Public  License  distributed  with  this  software;   see  file --
-- COPYING3.  If not, go to http://www.gnu.org/licenses for a complete copy --
-- of the license.                                                          --
------------------------------------------------------------------------------

with Ada.Containers.Hashed_Maps;
with Ada.Containers.Vectors;
with GNAT.Strings;
with System.Storage_Elements;

with GNATCOLL.VFS;       use GNATCOLL.VFS;

with GPS.Core_Kernels;
with GPS.Editors;
with GPS.Kernel.Hooks;   use GPS.Kernel.Hooks;
with GPS.Kernel.Messages.Simple;
with GPS.Kernel.Modules; use GPS.Kernel.Modules;
with GPS.Kernel.Project;
with GPS.LSP_Client.Editors;
with GPS.LSP_Client.Language_Servers.Real;
with GPS.LSP_Client.Language_Servers.Stub;
with GPS.LSP_Client.Text_Documents;
with GPS.LSP_Client.Utilities;
with Language;           use Language;
with LSP.Client_Notifications;
with LSP.Messages;
with LSP.Types;
with Src_Editor_Buffer;

package body GPS.LSP_Module is

   type Listener_Factory is
     new GPS.Core_Kernels.Editor_Listener_Factory with null record;

   overriding function Create
     (Self    : Listener_Factory;
      Editor  : GPS.Editors.Editor_Buffer'Class;
      Factory : GPS.Editors.Editor_Buffer_Factory'Class;
      Kernel  : GPS.Core_Kernels.Core_Kernel)
      return GPS.Editors.Editor_Listener_Access;

   type Buffer_Handler_Record is record
      Buffer  : GPS.Editors.Editor_Buffer_Holders.Holder;
      Handler : GPS.LSP_Client.Text_Documents.Text_Document_Handler_Access;
   end record;

   package Buffer_Handler_Vectors is
     new Ada.Containers.Vectors (Positive, Buffer_Handler_Record);

   function Hash (Value : Language_Access) return Ada.Containers.Hash_Type;

   package Language_Server_Maps is new Ada.Containers.Hashed_Maps
     (Key_Type        => Language_Access,
      Element_Type    =>
         GPS.LSP_Client.Language_Servers.Language_Server_Access,
      Hash            => Hash,
      Equivalent_Keys => "=",
      "="             => GPS.LSP_Client.Language_Servers."=");

   package Text_Document_Handler_Vectors is
     new Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type =>
           GPS.LSP_Client.Text_Documents.Text_Document_Handler_Access,
        "="          => GPS.LSP_Client.Text_Documents."=");

   type Module_Id_Record is
     new GPS.Kernel.Modules.Module_ID_Record
     and LSP.Client_Notifications.Client_Notification_Handler
     and GPS.LSP_Client.Text_Documents.Text_Document_Manager with
      record
         Language_Servers : Language_Server_Maps.Map;
         --  Map from language to LSP client

         Unknown_Server   :
           GPS.LSP_Client.Language_Servers.Language_Server_Access;
         --  Pseudo-server to handle managed text documents of language not
         --  supported by any configured language servers.

         Unmanaged        : Text_Document_Handler_Vectors.Vector;
         --  List of unmanaged text documents (not associated with any
         --  language server). Unmanaged documents are:
         --   - editor buffer of which is under constuction (editor listener
         --     was created, but "file_edited" hook was not called)
         --   - new files
         --   - files under renaming or save as operations
         --
         --  Only few elements are expected to be in this container, thus
         --  vector container is fine.
      end record;

   type LSP_Module_Id is access all Module_Id_Record'Class;

   overriding procedure Destroy (Self : in out Module_Id_Record);
   --  Stops all language server processes and cleanup data structures.

   overriding procedure Register
     (Self     : in out Module_Id_Record;
      Document :
        not null GPS.LSP_Client.Text_Documents.Text_Document_Handler_Access);
   --  Register new text document handler.

   overriding procedure Unregister
     (Self     : in out Module_Id_Record;
      Document :
        not null GPS.LSP_Client.Text_Documents.Text_Document_Handler_Access);
   --  Unregister text document handler.

   overriding procedure Associated
     (Self     : in out Module_Id_Record;
      Document :
        not null GPS.LSP_Client.Text_Documents.Text_Document_Handler_Access);
   --  Remove text document from the list of unmanaged text documents.

   overriding procedure Dissociated
     (Self     : in out Module_Id_Record;
      Document :
        not null GPS.LSP_Client.Text_Documents.Text_Document_Handler_Access);
   --  Add text document to the list of unmanaged text documents.

   procedure On_File_Closed_Or_Renamed
     (Self : in out Module_Id_Record'Class;
      File : GNATCOLL.VFS.Virtual_File);
   --  Called on "file_closed" and "file_renamed" hooks to move text document
   --  from managed to unmanaged state.

   overriding procedure Publish_Diagnostics
     (Self   : in out Module_Id_Record;
      Params : LSP.Messages.PublishDiagnosticsParams);

   procedure Initiate_Server_Shutdown
     (Self   : in out Module_Id_Record'Class;
      Lang   : not null Language.Language_Access;
      Server :
        not null GPS.LSP_Client.Language_Servers.Language_Server_Access);
   --  Initiate shutdown of the given language server for given language.

   procedure Initiate_Servers_Shutdown
     (Self    : in out Module_Id_Record'Class;
      Servers : in out Language_Server_Maps.Map'Class);
   --  Initiate shutdown of the given set of language servers and clears
   --  the set.

   Module : LSP_Module_Id;

   type On_File_Edited is new File_Hooks_Function with null record;
   overriding procedure Execute
     (Self   : On_File_Edited;
      Kernel : not null access Kernel_Handle_Record'Class;
      File   : Virtual_File);
   --  Called when a file has been opened

   type On_File_Closed is new File_Hooks_Function with null record;
   overriding procedure Execute
     (Self   : On_File_Closed;
      Kernel : not null access Kernel_Handle_Record'Class;
      File   : Virtual_File);
   --  Called before closing a buffer.

   type On_File_Renamed is new File2_Hooks_Function with null record;
   overriding procedure Execute
     (Self   : On_File_Renamed;
      Kernel : not null access Kernel_Handle_Record'Class;
      From   : GNATCOLL.VFS.Virtual_File;
      To     : GNATCOLL.VFS.Virtual_File);
   --  Called when file buffer is renamed.

   type On_Project_Changing is new File_Hooks_Function with null record;
   overriding procedure Execute
      (Self   : On_Project_Changing;
       Kernel : not null access Kernel_Handle_Record'Class;
       File   : GNATCOLL.VFS.Virtual_File);
   --  Called when project will be unloaded.

   type On_Project_View_Changed is new Simple_Hooks_Function with null record;
   overriding procedure Execute
      (Self   : On_Project_View_Changed;
       Kernel : not null access Kernel_Handle_Record'Class);

   Diagnostics_Messages_Category : constant String := "Diagnostics";
   Diagnostics_Messages_Flags    : constant
     GPS.Kernel.Messages.Message_Flags :=
       GPS.Kernel.Messages.Side_And_Locations;

   ----------------
   -- Associated --
   ----------------

   overriding procedure Associated
     (Self     : in out Module_Id_Record;
      Document :
        not null GPS.LSP_Client.Text_Documents.Text_Document_Handler_Access)
   is
      Position : Text_Document_Handler_Vectors.Cursor
        := Self.Unmanaged.Find (Document);

   begin
      Self.Unmanaged.Delete (Position);
   end Associated;

   ------------
   -- Create --
   ------------

   overriding function Create
     (Self    : Listener_Factory;
      Editor  : GPS.Editors.Editor_Buffer'Class;
      Factory : GPS.Editors.Editor_Buffer_Factory'Class;
      Kernel  : GPS.Core_Kernels.Core_Kernel)
      return GPS.Editors.Editor_Listener_Access
   is
      pragma Unreferenced (Self, Factory);

   begin
      --  Create, initialize and return object to integrate source editor and
      --  language server.

      return Result : constant GPS.Editors.Editor_Listener_Access :=
        new GPS.LSP_Client.Editors.Src_Editor_Handler
          (GPS.Kernel.Kernel_Handle (Kernel), Module)
      do
         declare
            Handler : GPS.LSP_Client.Editors.Src_Editor_Handler'Class
            renames GPS.LSP_Client.Editors.Src_Editor_Handler'Class
              (Result.all);
         begin
            Handler.Initialize (Editor);
            Module.Register (Handler'Unchecked_Access);
         end;
      end return;
   end Create;

   -------------
   -- Destroy --
   -------------

   overriding procedure Destroy (Self : in out Module_Id_Record) is
   begin
      for Server of Self.Language_Servers loop
         Server.Dissociate_All;
      end loop;

      while not Self.Unmanaged.Is_Empty loop
         Self.Unmanaged.First_Element.Destroy;
      end loop;
   end Destroy;

   -----------------
   -- Dissociated --
   -----------------

   overriding procedure Dissociated
     (Self     : in out Module_Id_Record;
      Document :
        not null GPS.LSP_Client.Text_Documents.Text_Document_Handler_Access) is
   begin
      Self.Unmanaged.Append (Document);
   end Dissociated;

   -------------
   -- Execute --
   -------------

   overriding procedure Execute
     (Self   : On_File_Closed;
      Kernel : not null access Kernel_Handle_Record'Class;
      File   : Virtual_File)
   is
      pragma Unreferenced (Self, Kernel);

   begin
      Module.On_File_Closed_Or_Renamed (File);
   end Execute;

   -------------
   -- Execute --
   -------------

   overriding procedure Execute
     (Self   : On_File_Edited;
      Kernel : not null access Kernel_Handle_Record'Class;
      File   : Virtual_File)
   is
      pragma Unreferenced (Self);

      Lang     : constant not null Language.Language_Access :=
        Kernel.Get_Language_Handler.Get_Language_From_File (File);
      Cursor   : constant Language_Server_Maps.Cursor :=
                   Module.Language_Servers.Find (Lang);
      Server   : GPS.LSP_Client.Language_Servers.Language_Server_Access;
      Position : Text_Document_Handler_Vectors.Cursor :=
                   Module.Unmanaged.First;

   begin
      if Language_Server_Maps.Has_Element (Cursor) then
         Server := Language_Server_Maps.Element (Cursor);

      else
         Server := Module.Unknown_Server;
      end if;

      while Text_Document_Handler_Vectors.Has_Element (Position) loop
         declare
            Document :
              GPS.LSP_Client.Text_Documents.Text_Document_Handler_Access
              renames Text_Document_Handler_Vectors.Element (Position);

         begin
            if Document.File = File then
               Server.Associate (Document);

               exit;
            end if;
         end;

         Text_Document_Handler_Vectors.Next (Position);
      end loop;
   end Execute;

   -------------
   -- Execute --
   -------------

   overriding procedure Execute
     (Self   : On_File_Renamed;
      Kernel : not null access Kernel_Handle_Record'Class;
      From   : GNATCOLL.VFS.Virtual_File;
      To     : GNATCOLL.VFS.Virtual_File)
   is
      pragma Unreferenced (Self, Kernel, To);

   begin
      Module.On_File_Closed_Or_Renamed (From);
   end Execute;

   -------------
   -- Execute --
   -------------

   overriding procedure Execute
      (Self   : On_Project_Changing;
       Kernel : not null access Kernel_Handle_Record'Class;
       File   : GNATCOLL.VFS.Virtual_File) is
      pragma Unreferenced (Self, Kernel, File);
   begin
      --  Shutdown all running language servers.

      Module.Initiate_Servers_Shutdown (Module.Language_Servers);
   end Execute;

   -------------
   -- Execute --
   -------------

   overriding procedure Execute
     (Self   : On_Project_View_Changed;
      Kernel : not null access Kernel_Handle_Record'Class)
   is
      pragma Unreferenced (Self);

      Languages       : GNAT.Strings.String_List :=
                          GPS.Kernel.Project.Get_Root_Project_View
                            (Kernel).Get_Project_Type.Languages (True);
      Running_Servers : Language_Server_Maps.Map := Module.Language_Servers;

   begin
      Module.Language_Servers.Clear;

      for Language_Name of Languages loop
         declare
            Lang     : constant not null Language.Language_Access :=
                         Kernel.Get_Language_Handler.Get_Language_By_Name
                           (Language_Name.all);
            Position : Language_Server_Maps.Cursor :=
                         Running_Servers.Find (Lang);
            Server   : GPS.LSP_Client.Language_Servers.Language_Server_Access;

         begin
            if Language_Server_Maps.Has_Element (Position) then
               --  Language server for the giving language is configured and
               --  runing; move it to new set of language servers

               Server := Language_Server_Maps.Element (Position);
               Language_Server_Maps.Delete (Running_Servers, Position);
               Module.Language_Servers.Insert (Lang, Server);

            else
               --  Start new language server if configured

               if Lang.Has_LSP then
                  Server :=
                    GPS.LSP_Client.Language_Servers.Real.Create
                      (Kernel, Module);

                  declare
                     S :  GPS.LSP_Client.Language_Servers.Real
                       .Real_Language_Server'Class
                         renames
                           GPS.LSP_Client.Language_Servers.Real
                             .Real_Language_Server'Class (Server.all);
                  begin
                     S.Client.Set_Notification_Handler (Module);
                     Module.Language_Servers.Insert (Lang, Server);
                     S.Client.Start (Lang.Get_LSP_Args);
                  end;
               end if;
            end if;

            GNAT.Strings.Free (Language_Name);
         end;
      end loop;

      --  Shutdown running language servers for unused languages

      Module.Initiate_Servers_Shutdown (Running_Servers);
   end Execute;

   ----------
   -- Hash --
   ----------

   function Hash (Value : Language_Access) return Ada.Containers.Hash_Type is
      X : constant System.Storage_Elements.Integer_Address :=
        System.Storage_Elements.To_Integer (Value.all'Address);
   begin
      return Ada.Containers.Hash_Type'Mod (X);
   end Hash;

   ------------------------------
   -- Initiate_Server_Shutdown --
   ------------------------------

   procedure Initiate_Server_Shutdown
     (Self   : in out Module_Id_Record'Class;
      Lang   : not null Language.Language_Access;
      Server : not null GPS.LSP_Client.Language_Servers.Language_Server_Access)
   is
      pragma Unreferenced (Self, Lang);

      S     :  GPS.LSP_Client.Language_Servers.Real.Real_Language_Server'Class
        renames GPS.LSP_Client.Language_Servers.Real.Real_Language_Server'Class
          (Server.all);
      Dummy : LSP.Types.LSP_Number;

   begin
      S.Client.Shutdown_Request (Dummy);
      --  ??? should wait till response received or timeout before send
      --  exit notification.

      S.Client.Exit_Notification;
   end Initiate_Server_Shutdown;

   -------------------------------
   -- Initiate_Servers_Shutdown --
   -------------------------------

   procedure Initiate_Servers_Shutdown
     (Self    : in out Module_Id_Record'Class;
      Servers : in out Language_Server_Maps.Map'Class) is
   begin
      while not Servers.Is_Empty loop
         declare
            Position : Language_Server_Maps.Cursor := Servers.First;

         begin
            Self.Initiate_Server_Shutdown
              (Language_Server_Maps.Key (Position),
               Language_Server_Maps.Element (Position));
            Servers.Delete (Position);
         end;
      end loop;
   end Initiate_Servers_Shutdown;

   -------------------------------
   -- On_File_Closed_Or_Renamed --
   -------------------------------

   procedure On_File_Closed_Or_Renamed
     (Self : in out Module_Id_Record'Class;
      File : GNATCOLL.VFS.Virtual_File)
   is
      Container : constant not null GPS.Kernel.Messages_Container_Access :=
                    Self.Get_Kernel.Get_Messages_Container;
      Lang      : constant not null Language.Language_Access :=
                    Self.Get_Kernel.Get_Language_Handler.Get_Language_From_File
                      (File);
      Position  : constant Language_Server_Maps.Cursor :=
                    Self.Language_Servers.Find (Lang);
      Server    : GPS.LSP_Client.Language_Servers.Language_Server_Access;

   begin
      Container.Remove_File
        (Diagnostics_Messages_Category, File, Diagnostics_Messages_Flags);

      if Language_Server_Maps.Has_Element (Position) then
         Server := Language_Server_Maps.Element (Position);

      else
         Server := Self.Unknown_Server;
      end if;

      declare
         use type GPS.LSP_Client.Text_Documents.Text_Document_Handler_Access;

         Document : GPS.LSP_Client.Text_Documents.Text_Document_Handler_Access
           renames Server.Text_Document (File);

      begin
         if Document /= null then
            --  Document is null then it represents new file without name. In
            --  this case it is not managed by any language server objects.

            Server.Dissociate (Server.Text_Document (File));
         end if;
      end;
   end On_File_Closed_Or_Renamed;

   -------------------------
   -- Publish_Diagnostics --
   -------------------------

   overriding procedure Publish_Diagnostics
     (Self   : in out Module_Id_Record;
      Params : LSP.Messages.PublishDiagnosticsParams)
   is
      function To_Importance
        (Item : LSP.Messages.Optional_DiagnosticSeverity)
         return GPS.Kernel.Messages.Message_Importance_Type;
      --  Convert LSP's DiagnosticSeverity type to GPS's
      --  Message_Importance_Type.

      -------------------
      -- To_Importance --
      -------------------

      function To_Importance
        (Item : LSP.Messages.Optional_DiagnosticSeverity)
         return GPS.Kernel.Messages.Message_Importance_Type is
      begin
         if not Item.Is_Set then
            return GPS.Kernel.Messages.High;

         else
            case Item.Value is
            when LSP.Messages.Error =>
               return GPS.Kernel.Messages.High;

            when LSP.Messages.Warning =>
               return GPS.Kernel.Messages.Medium;

            when LSP.Messages.Information =>
               return GPS.Kernel.Messages.Low;

            when LSP.Messages.Hint =>
               return GPS.Kernel.Messages.Informational;
            end case;
         end if;
      end  To_Importance;

      Container : constant not null GPS.Kernel.Messages_Container_Access :=
                    Self.Get_Kernel.Get_Messages_Container;
      File      : constant GNATCOLL.VFS.Virtual_File :=
                    GPS.LSP_Client.Utilities.To_Virtual_File (Params.uri);

   begin
      Container.Remove_File
        (Diagnostics_Messages_Category, File, Diagnostics_Messages_Flags);

      for Diagnostic of Params.diagnostics loop
         GPS.Kernel.Messages.Simple.Create_Simple_Message
           (Container                => Container,
            Category                 => Diagnostics_Messages_Category,
            File                     => File,
            Line                     =>
              Integer (Diagnostic.span.first.line) + 1,
            Column                   =>
              GPS.LSP_Client.Utilities.UTF_16_Offset_To_Visible_Column
                (Diagnostic.span.first.character),
            Text                     =>
              LSP.Types.To_UTF_8_String (Diagnostic.message),
            Importance               => To_Importance (Diagnostic.severity),
            Flags                    => Diagnostics_Messages_Flags,
            Allow_Auto_Jump_To_First => False);
      end loop;
   end Publish_Diagnostics;

   --------------
   -- Register --
   --------------

   overriding procedure Register
     (Self     : in out Module_Id_Record;
      Document :
        not null GPS.LSP_Client.Text_Documents.Text_Document_Handler_Access)
   is
   begin
      Self.Unmanaged.Prepend (Document);
   end Register;

   ---------------------
   -- Register_Module --
   ---------------------

   procedure Register_Module (Kernel : Kernel_Handle) is
   begin
      Module := new Module_Id_Record;
      Module.Unknown_Server :=
        new GPS.LSP_Client.Language_Servers.Stub.Stub_Language_Server (Module);
      Register_Module (Module_ID (Module), Kernel, "LSP_Client");
      File_Edited_Hook.Add (new On_File_Edited);
      File_Closed_Hook.Add (new On_File_Closed);
      File_Renamed_Hook.Add (new On_File_Renamed);
      Project_Changing_Hook.Add (new On_Project_Changing);
      Project_View_Changed_Hook.Add (new On_Project_View_Changed);

      Src_Editor_Buffer.Add_Listener_Factory (new Listener_Factory);
   end Register_Module;

   ----------------
   -- Unregister --
   ----------------

   overriding procedure Unregister
     (Self     : in out Module_Id_Record;
      Document :
        not null GPS.LSP_Client.Text_Documents.Text_Document_Handler_Access)
   is
      Position : Text_Document_Handler_Vectors.Cursor :=
                   Self.Unmanaged.Find (Document);

   begin
      if Text_Document_Handler_Vectors.Has_Element (Position) then
         Self.Unmanaged.Delete (Position);

      else
         raise Program_Error with "Managed or unknown text document";
      end if;
   end Unregister;

end GPS.LSP_Module;
