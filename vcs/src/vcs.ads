-----------------------------------------------------------------------
--                          G L I D E  I I                           --
--                                                                   --
--                      Copyright (C) 2001 - 2002                    --
--                            ACT-Europe                             --
--                                                                   --
-- GLIDE is free software; you can redistribute it and/or modify  it --
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

with Generic_List;
with String_List;

with Commands;

with Glide_Kernel; use Glide_Kernel;

package VCS is

   --  This package provides utilities for communicating with a VCS
   --  repository. It provides a general architecture which is common
   --  to all VCS systems.
   --
   --  Depending on what the underlying VCS is like, some operations might
   --  be more costly than others,
   --  Therefore we provide two kinds of access to a VCS repository :
   --  either by reading multiple entries at a time,
   --  or by reading one entry at a time.
   --
   --  All queries are configurable, ie the amount of information
   --  that we communicate can be decided by the user.

   type VCS_Record is abstract tagged limited private;
   --  A value used to reference a VCS repository.

   type VCS_Access is access all VCS_Record'Class;

   function Get_VCS_From_Id (Id : String) return VCS_Access;
   --  Browse through all VCS identifiers that are registered and return
   --  a VCS reference to an appropriate system, if any.
   --  If no satisfying system was found, Null is returned.
   --  VCS identifiers are registered using Register_VCS_Identifier.

   type VCS_Id_Identifier is access
     function (Id : in String) return VCS_Access;

   procedure Register_VCS_Identifier (Identifier : VCS_Id_Identifier);
   --  Add an identifier to the list of known identifiers.
   --  See Get_VCS_From_Id above.

   procedure Free (Ref : access VCS_Record);
   --  Free memory associated with Ref.
   --  ??? is this the correct way to do it ?

   type File_Status is
     (Unknown,
      --  The status is not yet determined or the VCS repository is not able to
      --  tell (disconnected, locked, broken, etc)

      Not_Registered,
      --  The file is unknown of the VCS repository.

      Up_To_Date,
      --  The file corresponds to the latest version in the corresponding
      --  branch on the repository.

      Removed,
      --  The file still exists locally but is known to have been removed from
      --  the VCS repository.

      Modified,
      --  The file has been modified by the user or has been explicitly opened
      --  for editing.

      Needs_Merge,
      --  The file has been modified locally and on the repository.

      Needs_Update
      --  The file has been modified in the repository but not locally.
     );

   type File_Status_Record is record
      --  Contains all the repository information concerning one file.

      File_Name : String_List.List := String_List.Null_List;
      --  The absolute local name of the file.

      Status : File_Status := Unknown;
      --  The status of the file.

      Working_Revision : String_List.List := String_List.Null_List;
      --  The current local version of the file.

      Repository_Revision : String_List.List := String_List.Null_List;
      --  The latest version of the file in the repository.

      Tags    : String_List.List := String_List.Null_List;
      --  Other versions of this file that exist in the repository.

      Users : String_List.List := String_List.Null_List;
      --  A list of users currently working on the file.

      --  ???  We need to put additional info here : date, etc.
   end record;

   function Copy_String_List
     (S : in String_List.List) return String_List.List;
   --  Return a deep copy of S.

   function Copy_File_Status
     (F : in File_Status_Record) return File_Status_Record;
   --  Return a deep copy of F.

   procedure Free (F : in out File_Status_Record);
   package File_Status_List is new Generic_List (File_Status_Record);

   procedure Get_Status
     (Rep         : access VCS_Record;
      Filenames   :        String_List.List) is abstract;
   --  Return the status of a list of files.
   --  The returned File_Status_Record is to be filled only with information
   --  that have the corresponding parameter set to True, all the other fields
   --  are empty lists.
   --
   --  Filenames must be a list of absolute file names or absolute
   --  directory names.
   --  If the list contains file names then the returned list must correspond
   --  to the order in Filenames.
   --
   --  Implementations for this procedure should document which fields are
   --  costly to obtain and which are easy.
   --
   --  ??? The behaviour is undetermined when the Filenames list
   --  has duplicate entries, or empty/invalid entries.

   function Local_Get_Status
     (Rep         : access VCS_Record;
      Filenames   : String_List.List) return File_Status_List.List is abstract;
   --  Return the status of a list of files.
   --  This function only attempts to read information from local data, and
   --  does not connect to the repository.
   --  It is therefore faster than Get_Status but cannot find all information.
   --  Filenames can simply be a list of directories, in which case
   --  the function will return information about all files in those
   --  directories.

   procedure Open
     (Rep       : access VCS_Record;
      Filenames : String_List.List;
      User_Name : String := "") is abstract;
   --  Open the a file for modification.
   --  This is a necessary step for some systems but not all of them.
   --  If User_Name is not empty, then add it to the list of users
   --  editing the file, whenever possible.

   procedure Commit
     (Rep       : access VCS_Record;
      Filenames : String_List.List;
      Logs      : String_List.List) is abstract;
   --  Check a file Name in the specified repository.
   --  Log is used as the revision history.
   --  The elements in Logs must exactly correspond to the elements in
   --  Filenames.

   procedure Update
     (Rep       : access VCS_Record;
      Filenames : String_List.List) is abstract;
   --  Synchronize the local files or directories.

   procedure Merge
     (Rep       : access VCS_Record;
      Filenames : String_List.List) is abstract;
   --  Merge the files from the specified repository with the local files.
   --  The merge is done locally, a commit is required to pass the
   --  resulting changes to the repository.

   procedure Add
     (Rep       : access VCS_Record;
      Filenames : String_List.List) is abstract;
   --  Add files to the specified VCS repository

   procedure Remove
     (Rep       : access VCS_Record;
      Filenames : String_List.List) is abstract;
   --  Remove a given file/directory name from the specified VCS repository

   procedure Revert
     (Rep       : access VCS_Record;
      Filenames : String_List.List) is abstract;
   --  Obtain the files in Filenames from their respective checked-in versions.

   procedure Diff
     (Rep       : access VCS_Record;
      File      : String;
      Version_1 : String := "";
      Version_2 : String := "") is abstract;
   --  Return a diff between two versions of one file.
   --  The result is a String_List.List with one element for each line,
   --  in the standard basic diff format.
   --  If Version_1 is empty, then the local file is taken.
   --  If Version_2 is empty, then the HEAD revision is taken.

   procedure Log
     (Rep  : access VCS_Record;
      File : String) is abstract;
   --  Return a changelog for the corresponding file.
   --  The result String_List.List with one element for each line.

   procedure Annotate
     (Rep  : access VCS_Record;
      File : String) is abstract;
   --  Return annotations for the corresponding file.
   --  The result String_List.List with one element for each line.

   procedure Set_Error
     (Rep            : access VCS_Record;
      Message        : String;
      Add_LF         : Boolean := True);
   --  Display message in the glide console.

   --  ??? missing:
   --  init
   --  tag
   --  other version

private
   type VCS_Record is abstract tagged limited record
      Kernel : Glide_Kernel.Kernel_Handle;
      Queue  : Commands.Command_Queue;
   end record;

end VCS;
