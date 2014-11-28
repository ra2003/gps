------------------------------------------------------------------------------
--                                  G P S                                   --
--                                                                          --
--                     Copyright (C) 2003-2014, AdaCore                     --
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

with Language.Abstract_Language_Tree; use Language.Abstract_Language_Tree;
with GPS.Core_Kernels; use GPS.Core_Kernels;
with Language.Tree; use Language.Tree;
with Ada.Containers; use Ada.Containers;
with Libclang.Index; use Libclang.Index;
with Ada.Containers.Indefinite_Holders;
with Ada.Containers.Doubly_Linked_Lists;
with clang_c_Index_h; use clang_c_Index_h;

package Language.Libclang_Tree is

   package Clang_Iterator_Lists
   is new Ada.Containers.Doubly_Linked_Lists (Clang_Cursor);

   package Clang_Iterator_Lists_Ref
   is new Ada.Containers.Indefinite_Holders
     (Clang_Iterator_Lists.List,
      "=" => Clang_Iterator_Lists."=");

   ----------------------
   -- Type definitions --
   ----------------------

   type Clang_Tree_Provider is new Semantic_Tree_Provider with record
      Kernel : Core_Kernel;
   end record;
   type Clang_Tree_Provider_Access is access all Clang_Tree_Provider;

   type Abstract_Clang_Tree is new Semantic_Tree with record
      Kernel : Core_Kernel;
      File   : GNATCOLL.VFS.Virtual_File;
      Tu     : Clang_Translation_Unit;
   end record;
   type Clang_Tree_Access is access all Abstract_Clang_Tree;

   type Clang_Node is new Semantic_Node with record
      Kernel : Core_Kernel;
      Cursor : Clang_Cursor;
      Ref_File : GNATCOLL.VFS.Virtual_File;
   end record;
   type Clang_Node_Access is access all Clang_Node;

   type Clang_Tree_Iterator is new Semantic_Tree_Iterator with record
      Kernel : Core_Kernel;
      File   : GNATCOLL.VFS.Virtual_File;
      Elements : Clang_Iterator_Lists_Ref.Holder;
      Current_Cursor : Clang_Iterator_Lists.Cursor
        := Clang_Iterator_Lists.No_Element;
      Current_Children_Added : Boolean;
   end record;

   ------------------------------------
   -- Clang_Tree_Provider primitives --
   ------------------------------------

   function Create (K : Core_Kernel) return Semantic_Tree_Provider_Access;

   overriding function Get_Tree_For_File
     (Self : Clang_Tree_Provider;
      File : GNATCOLL.VFS.Virtual_File) return Semantic_Tree'Class;

   ------------------------------------
   -- Abstract_Clang_Tree primitives --
   ------------------------------------

   overriding function Root_Nodes
     (Self : Abstract_Clang_Tree) return Semantic_Node_Array'Class;

   overriding function Root_Iterator
     (Self : Abstract_Clang_Tree) return Semantic_Tree_Iterator'Class;

   overriding function Node_At
     (Self : Abstract_Clang_Tree; Sloc : Sloc_T;
      Category_Filter : Category_Array := Null_Category_Array)
      return Semantic_Node'Class;

   overriding function File
     (Self : Abstract_Clang_Tree) return GNATCOLL.VFS.Virtual_File;

   overriding procedure Update
     (Self : Abstract_Clang_Tree);

   ---------------------------
   -- Clang_Node primitives --
   ---------------------------

   overriding function Category
     (Self : Clang_Node) return Language_Category;

   overriding function Parent
     (Self : Clang_Node) return Semantic_Node'Class;

   overriding function Children
     (Self : Clang_Node) return Semantic_Node_Array'Class;

   overriding function First_Child
     (Self : Clang_Node) return Semantic_Node'Class;

   overriding function Name
     (Self : Clang_Node) return GNATCOLL.Symbols.Symbol;

   overriding function Profile
     (Self : Clang_Node) return String;

   overriding function Is_Valid
     (Self : Clang_Node) return Boolean is (True);

   overriding function Definition
     (Self : Clang_Node) return Semantic_Node'Class;

   overriding function Sloc_Def
     (Self : Clang_Node) return Sloc_T;

   overriding function Sloc_Start
     (Self : Clang_Node) return Sloc_T;

   overriding function Sloc_End
     (Self : Clang_Node) return Sloc_T;

   overriding function Get_Hash
     (Self : Clang_Node) return Hash_Type;

   overriding function File
     (Self : Clang_Node) return GNATCOLL.VFS.Virtual_File;

   overriding function Is_Declaration
     (Self : Clang_Node) return Boolean;

   overriding function Visibility
     (Self : Clang_Node) return Semantic_Node_Visibility;

   overriding function Unique_Id
     (Self : Clang_Node) return String;

   overriding function Info
     (Self : Clang_Node) return Semantic_Node_Info;

   overriding function Documentation_Body
     (Self : Clang_Node) return String;

   overriding function Documentation_Header
     (Self : Clang_Node) return String;

   overriding procedure Next (It : in out Clang_Tree_Iterator);

   overriding function Element
     (It : Clang_Tree_Iterator) return Semantic_Node'Class;

   overriding function Has_Element
     (It : Clang_Tree_Iterator) return Boolean;

   function To_Sloc_T (Arg : CXSourceLocation) return Sloc_T;

private

   --------------------------------------------------------------------------
   -- Private definition of Clang_Node_Array and associated primitives --
   --------------------------------------------------------------------------

   package Cursors_Holders is new Ada.Containers.Indefinite_Holders
     (Cursors_Vectors.Vector, Cursors_Vectors."=");

   type Clang_Node_Array is new Semantic_Node_Array with record
      Nodes  : Cursors_Holders.Holder;
      --  We're using the holder here to give reference semantics to node,
      --  you can do as many copies of a Clang_Node_Array instance, there
      --  will always be only one children vector
      Kernel : Core_Kernel;
      File   : GNATCOLL.VFS.Virtual_File;
   end record;

   function Get
     (Self : Clang_Node_Array; Index : Positive) return Semantic_Node'Class
   is
     (Clang_Node'(Self.Kernel, Self.Nodes.Element.Element (Index), Self.File));

   function Length (Self : Clang_Node_Array) return Natural is
     (Natural (Self.Nodes.Element.Length));

end Language.Libclang_Tree;
