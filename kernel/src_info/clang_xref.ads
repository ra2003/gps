with Xref; use Xref;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Language_Handlers; use Language_Handlers;
with Language.Profile_Formaters; use Language.Profile_Formaters;
with GNATCOLL.VFS;
with GPS.Core_Kernels; use GPS.Core_Kernels;

package Clang_Xref is

   type Clang_Database is new Lang_Specific_Database with record
      Kernel : Core_Kernel;
   end record;

   type Clang_Entity is new Root_Entity with record
      Kernel : Core_Kernel;
      General_Db : General_Xref_Database;
      Name : Unbounded_String;
      Loc : General_Location;
   end record;

   overriding function Get_Entity
     (Db : Clang_Database;
      General_Db : General_Xref_Database;
      Name : String;
      Loc : General_Location) return Root_Entity'Class;

   overriding function Is_Fuzzy (Entity : Clang_Entity) return Boolean;
   --  Whether the entity is just a guess (because the xref info generated by
   --  the compiler was not up-to-date).

   overriding function Get_Name
     (Entity : Clang_Entity) return String;
   --  Return the name of the entity

   overriding function Get_Display_Kind
     (Entity : Clang_Entity) return String;
   --  Return a general kind for the entity. This is not its type, more like a
   --  metaclass. Its exact value will vary depending on what was inserted in
   --  the database, and new language can insert new kinds at any time. So this
   --  string should only be used for display.

   overriding function Qualified_Name
     (Entity : Clang_Entity) return String;
   --  Return the fully qualified name of the entity

   overriding function Hash
     (Entity : Clang_Entity) return Integer;
   --  Return a hash code for the entity

   function Cmp
     (Entity1, Entity2 : Root_Entity'Class) return Integer;
   --  Return -1, 0 or 1 to sort the two entities

   overriding function Get_Declaration
     (Entity : Clang_Entity) return General_Entity_Declaration;
   --  Return the location of the entity declaration

   overriding function Caller_At_Declaration
     (Entity : Clang_Entity) return Root_Entity'Class;
   --  Return the entity whose scope contains the declaration of Entity

   overriding function Get_Body
     (Entity : Clang_Entity;
      After  : General_Location := No_Location)
      return General_Location;
   --  Return the location of the first body for this entity

   overriding function Get_Type_Of
     (Entity : Clang_Entity) return Root_Entity'Class;
   --  Return the type of the entity

   overriding function Returned_Type
     (Entity : Clang_Entity) return Root_Entity'Class;
   --  Return the type returned by a function.

   overriding function Parent_Package
     (Entity : Clang_Entity) return Root_Entity'Class;
   --  Return the parent package (if Entity is a package itself)

   overriding function Pointed_Type
     (Entity : Clang_Entity) return Root_Entity'Class;
   --  The type pointed to by an access type. Returns null for a variable.

   overriding function Renaming_Of
     (Entity : Clang_Entity) return Root_Entity'Class;
   --  Return the entity that Entity renames (or No_General_Entity)

   overriding function Is_Primitive_Of
     (Entity : Clang_Entity) return Entity_Array;
   --  Returns the entities for which Entity is a method/primitive operation
   --  (including the entities for which it is an inherited method)
   --  Caller must call Free on the result.

   overriding function Has_Methods (E : Clang_Entity) return Boolean;
   --  True if the entity might have methods

   overriding function Is_Access (E : Clang_Entity) return Boolean;
   --  True if E is a type or a variable, and it points to some other type.
   --  This is an Ada access type, an Ada access variable, a C pointer,...

   overriding function Is_Abstract
     (E  : Clang_Entity) return Boolean;
   --  Whether the entity (ie cannot be instantiated

   overriding function Is_Array
     (E  : Clang_Entity) return Boolean;
   --  Whether E is an array type or variable. This is mostly used in the
   --  debugger to find whether the user should be able to dereference the
   --  variable.

   overriding function Is_Printable_In_Debugger
     (E  : Clang_Entity) return Boolean;
   --  Whether we can execute a "print" on E in a debugger, and get a value
   --  that can be shown to the user.
   --  ??? We could perhaps try the command in gdb directly and guess from
   --  there

   overriding function Is_Type
     (E  : Clang_Entity) return Boolean;
   --  True f E is a type (not a variable or a package for instance)

   overriding function Is_Subprogram
     (E  : Clang_Entity) return Boolean;
   --  True if E is a subprogram

   overriding function Is_Container
     (E  : Clang_Entity) return Boolean;
   --  True if E can contain other entities (a record, struct,...)

   overriding function Is_Generic
     (E  : Clang_Entity) return Boolean;
   --  Whether the entity is a 'generic' or 'template'

   overriding function Is_Global
     (E  : Clang_Entity) return Boolean;
   --  Whether the entity is a global entity (library-level in Ada)

   overriding function Is_Static_Local
     (E  : Clang_Entity) return Boolean;
   --  Whether the entity is a static, in the C/C++ sense.

   overriding function Is_Predefined_Entity
     (E  : Clang_Entity) return Boolean;
   --  True if E is a predefined entity

   overriding procedure Documentation
     (Handler           : Language_Handlers.Language_Handler;
      Entity            : Clang_Entity;
      Formater          : access Profile_Formater'Class;
      Check_Constructs  : Boolean := True;
      Look_Before_First : Boolean := True);
   --  Return the documentation (tooltips,...) for the entity.
   --  Formater is responsible for formating and keep resulting text.
   --  Check_Constructs should be False to disable the use of the constructs
   --  database.
   --
   --  If Look_Before_First is True, the comments are first searched before
   --  the entity, and if not found after the entity. Otherwise the search
   --  order is reversed.
   --
   --  ??? Do we need to pass Handler?

   overriding function End_Of_Scope
     (Entity : Clang_Entity) return General_Location;
   --  For type declaration return the location of their syntax scope; for
   --  Ada packages and subprograms return the location of the end of scope
   --  of their body.

   overriding function Is_Parameter_Of
     (Entity : Clang_Entity) return Root_Entity'Class;
   --  Return the subprogram for which entity is a parameter

   overriding function Overrides
     (Entity : Clang_Entity) return Root_Entity'Class;
   --  The entity that Entity overrides.

   overriding function Instance_Of
     (Entity : Clang_Entity) return Root_Entity'Class;
   --  Return the generic entity instantiated by Entity

   overriding function Methods
     (Entity            : Clang_Entity;
      Include_Inherited : Boolean) return Entity_Array;
   --  The list of methods of an entity.

   overriding function Fields
     (Entity            : Clang_Entity) return Entity_Array;
   --  The fields of an Ada record or C struct

   overriding function Literals
     (Entity            : Clang_Entity) return Entity_Array;
   --  Return the literals of an enumeration

   overriding function Formal_Parameters
     (Entity            : Clang_Entity) return Entity_Array;
   --  The formal parameters for a generic entity.

   overriding function Discriminant_Of
     (Entity            : Clang_Entity) return Root_Entity'Class;
   --  Return the Ada record for which Entity is a discriminant

   overriding function Discriminants
     (Entity            : Clang_Entity) return Entity_Array;
   --  Return the list of discriminants for the entity

   overriding function Component_Type
     (Entity : Clang_Entity) return Root_Entity'Class;
   overriding function Index_Types
     (Entity : Clang_Entity) return Entity_Array;
   --  Index and components types for an array

   overriding function Child_Types
     (Entity    : Clang_Entity;
      Recursive : Boolean) return Entity_Array;
   --  Return the list of types derived from Entity (in the type-extension
   --  sense).

   overriding function Parent_Types
     (Entity    : Clang_Entity;
      Recursive : Boolean) return Entity_Array;
   --  Return the list of types that Entity extends.

   overriding function Parameters
     (Entity : Clang_Entity) return Parameter_Array;
   --  Return the list of parameters for a given subprogram

   overriding function Get_All_Called_Entities
     (Entity : Clang_Entity) return Abstract_Entities_Cursor'Class;
   --  Return all the entities that are found in the scope of Entity. This is
   --  not necessarily a subprogram call, but can be many things.
   --  All entities returned are unique. If you need to find the specific
   --  reference(s) to that entity, you'll need to search for the references in
   --  the right scope through the iterators above.

   overriding function Find_All_References
     (Entity                : Clang_Entity;
      In_File               : GNATCOLL.VFS.Virtual_File :=
        GNATCOLL.VFS.No_File;
      In_Scope              : Root_Entity'Class := No_Root_Entity;
      Include_Overriding    : Boolean := False;
      Include_Overridden    : Boolean := False;
      Include_Implicit      : Boolean := False;
      Include_All           : Boolean := False;
      Kind                  : String := "")
      return Root_Reference_Iterator'Class;

end Clang_Xref;
