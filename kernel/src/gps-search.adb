------------------------------------------------------------------------------
--                                  G P S                                   --
--                                                                          --
--                     Copyright (C) 2013, AdaCore                          --
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

with Ada.Characters.Handling;     use Ada.Characters.Handling;
with Ada.Strings.Unbounded;       use Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with GNATCOLL.Boyer_Moore;        use GNATCOLL.Boyer_Moore;
with GNATCOLL.Traces;             use GNATCOLL.Traces;
with GNAT.Expect;
with GNAT.Regpat;                 use GNAT.Regpat;
with GNAT.Strings;                use GNAT.Strings;
with Glib.Convert;
with Interfaces;                  use Interfaces;
with Unicode.CES.Utf8;            use Unicode, Unicode.CES.Utf8;

package body GPS.Search is
   Me : constant Trace_Handle := Create ("SEARCH");
   Memcheck_Handle : constant Trace_Handle := Create ("TESTSUITE.MEM", Off);

   type Boyer_Moore_Pattern_Access is access all GNATCOLL.Boyer_Moore.Pattern;
   type Match_Array_Access is access GNAT.Regpat.Match_Array;

   type Full_Text_Search is new Search_Pattern with record
      Pattern : Boyer_Moore_Pattern_Access;
      Length  : Natural;
   end record;

   type Regexp_Search is new Search_Pattern with record
      Pattern : GNAT.Expect.Pattern_Matcher_Access;
      Matches : Match_Array_Access;
   end record;

   type Fuzzy_Search is new Search_Pattern with null record;

   Approximate_Max_Errors        : constant := 2;
   Approximate_Insertion_Cost    : constant := 1;
   Approximate_Substitution_Cost : constant := 1;
   Approximate_Deletion_Cost     : constant := 1;
   --  The cost for character insertion, substitution or deletion. Set any of
   --  these to Integer'Last to disable this type of errors.

   Approximate_Max_Cost : constant :=
     Integer'Max
       (Integer'Max
            (Integer'Max
                 (Approximate_Insertion_Cost,
                  Approximate_Substitution_Cost),
             Approximate_Deletion_Cost),
        Approximate_Max_Errors);

   subtype Mask is Interfaces.Unsigned_64;
   --  We only consider the 1..Pattern'Length

   type Character_Mask_Array is array (Unicode_Char range <>) of Mask;
   type Character_Masks is access all Character_Mask_Array;
   type Approximate_Status is
     array (-Approximate_Max_Cost .. Approximate_Max_Errors) of Mask;
   type Approximate_Status_Access is access all Approximate_Status;

   type Approximate_Search is new Search_Pattern with record
      Pattern : Character_Masks;
      --  Precomputed info about the pattern
      --  ??? We only need entries for the characters in the Pattern, so we
      --  are wasting space here. This would also allow working with UTF8
      --  characters.

      Max_Errors : Natural := Approximate_Max_Errors;

      Result : Approximate_Status_Access;
      --  ??? This would be better part of the search context

      Matched : Mask;
      --  Value in Result that indicates when the character matches
   end record;
   type Approximate_Search_Access is access all Approximate_Search'Class;
   --  An approximate matcher. The algorithm is from:
   --    http://en.wikipedia.org/wiki/Bitap_algorithm
   --    from Wu and Manber "Fast Text Searching With Errors"

   function Compile_Approximate
     (Pattern         : String;
      Case_Sensitive  : Boolean;
      Whole_Word      : Boolean;
      Allow_Highlight : Boolean;
      Negate          : Boolean) return Approximate_Search_Access;
   --  Compile the pattern

   overriding function Start
     (Self        : Full_Text_Search;
      Buffer      : String;
      Start_Index : Integer := -1;
      End_Index   : Integer := -1;
      Ref_Index   : Integer := -1;
      Ref_Line    : Natural := 1;
      Ref_Column  : Character_Offset_Type := 1;
      Ref_Visible_Column : Visible_Column_Type := -1) return Search_Context;
   overriding function Start
     (Self        : Regexp_Search;
      Buffer      : String;
      Start_Index : Integer := -1;
      End_Index   : Integer := -1;
      Ref_Index   : Integer := -1;
      Ref_Line    : Natural := 1;
      Ref_Column  : Character_Offset_Type := 1;
      Ref_Visible_Column : Visible_Column_Type := -1) return Search_Context;
   overriding function Start
     (Self        : Fuzzy_Search;
      Buffer      : String;
      Start_Index : Integer := -1;
      End_Index   : Integer := -1;
      Ref_Index   : Integer := -1;
      Ref_Line    : Natural := 1;
      Ref_Column  : Character_Offset_Type := 1;
      Ref_Visible_Column : Visible_Column_Type := -1) return Search_Context;
   overriding function Start
     (Self        : Approximate_Search;
      Buffer      : String;
      Start_Index : Integer := -1;
      End_Index   : Integer := -1;
      Ref_Index   : Integer := -1;
      Ref_Line    : Natural := 1;
      Ref_Column  : Character_Offset_Type := 1;
      Ref_Visible_Column : Visible_Column_Type := -1) return Search_Context;
   overriding procedure Next
     (Self    : Full_Text_Search;
      Buffer  : String;
      Context : in out Search_Context);
   overriding procedure Next
     (Self    : Regexp_Search;
      Buffer  : String;
      Context : in out Search_Context);
   overriding procedure Next
     (Self    : Fuzzy_Search;
      Buffer  : String;
      Context : in out Search_Context);
   overriding procedure Next
     (Self    : Approximate_Search;
      Buffer  : String;
      Context : in out Search_Context);
   overriding procedure Free (Self : in out Full_Text_Search);
   overriding procedure Free (Self : in out Approximate_Search);
   overriding procedure Free (Self : in out Regexp_Search);
   overriding function Highlight_Match
      (Self    : Fuzzy_Search;
       Buffer  : String;
       Context : Search_Context) return String;

   procedure Update_Location
     (Context : in out Search_Context;
      Buffer  : String);
   --  Compute the (line, column) location for the match, based on previous
   --  knowledge in Context.

   function "<" (P1, P2 : Provider_Info) return Boolean;
   function "<" (P1, P2 : Provider_Info) return Boolean is
   begin
      return P1.Provider.Rank < P2.Provider.Rank;
   end "<";

   package Sorting_By_Rank is new Provider_Lists.Generic_Sorting ("<");

   ---------------------
   -- Update_Location --
   ---------------------

   procedure Update_Location
     (Context : in out Search_Context;
      Buffer  : String)
   is
      Tab_Width : constant Visible_Column_Type := 8;
      --  Visible_Column_Type (Vsearch.Get_Tab_Width);

      C : Character;
   begin
      while Context.Ref_Index < Context.Finish
        and then Context.Ref_Index < Context.Buffer_End
      loop
         Context.Ref_Index := Context.Ref_Index + 1;

         C := Buffer (Context.Ref_Index);

         if C = ASCII.LF
           or else (C = ASCII.CR
                    and then Context.Ref_Index < Context.Buffer_End
                    and then Buffer (Context.Ref_Index + 1) /= ASCII.LF)
         then
            Context.Ref_Line := Context.Ref_Line + 1;
            Context.Ref_Column := 0;

         elsif C = ASCII.HT then
            Context.Ref_Column := Context.Ref_Column + 1;
            Context.Ref_Visible_Column := Context.Ref_Visible_Column
              + Tab_Width - (Context.Ref_Visible_Column mod Tab_Width) + 1;
         else
            Context.Ref_Column := Context.Ref_Column + 1;
            Context.Ref_Visible_Column := Context.Ref_Visible_Column + 1;
         end if;

         if Context.Ref_Index = Context.Start then
            Context.Line_Start := Context.Ref_Line;
            Context.Col_Start := Context.Ref_Column;
            Context.Col_Visible_Start := Context.Ref_Visible_Column;
         end if;

         if Context.Ref_Index = Context.Finish then
            Context.Line_End := Context.Ref_Line;
            Context.Col_End := Context.Ref_Column;
            Context.Col_Visible_End := Context.Ref_Visible_Column;
         end if;
      end loop;
   end Update_Location;

   -----------
   -- Start --
   -----------

   overriding function Start
     (Self        : Full_Text_Search;
      Buffer      : String;
      Start_Index : Integer := -1;
      End_Index   : Integer := -1;
      Ref_Index   : Integer := -1;
      Ref_Line    : Natural := 1;
      Ref_Column  : Character_Offset_Type := 1;
      Ref_Visible_Column : Visible_Column_Type := -1) return Search_Context
   is
      Index : Integer;
      S : constant Integer :=
        (if Start_Index = -1 then Buffer'First else Start_Index);
      F : constant Integer :=
        (if End_Index = -1 then Buffer'Last else End_Index);
      R : constant Integer :=
        (if Ref_Index = -1 then Buffer'First else Ref_Index);
      Context : Search_Context;
   begin
      Index := GNATCOLL.Boyer_Moore.Search (Self.Pattern.all, Buffer (S .. F));
      if Index = -1 then
         if Self.Negate then
            Context := Search_Context'
              (Start              => S,
               Finish             => F,
               Line_Start         => 1,
               Line_End           => 1,
               Col_Start          => 1,
               Col_End            => 1,
               Col_Visible_Start  => 1,
               Col_Visible_End    => 1,
               Score              => 50,
               Buffer_Start       => S,
               Buffer_End         => F,
               Ref_Index          => R,
               Ref_Line           => Ref_Line,
               Ref_Column         => Ref_Column,
               Ref_Visible_Column =>
                 (if Ref_Visible_Column = -1
                  then Visible_Column_Type (Ref_Column)
                  else Ref_Visible_Column));
         else
            Context := No_Match;
         end if;
      elsif Self.Negate then
         Context := No_Match;
      else
         Context := Search_Context'
           (Start              => Index,
            Finish             => Index + Self.Length - 1,
            Line_Start         => 1,
            Line_End           => 1,
            Col_Start          => 1,
            Col_End            => 1,
            Col_Visible_Start  => 1,
            Col_Visible_End    => 1,
            Score              => 100,
            Buffer_Start       => S,
            Buffer_End         => F,
            Ref_Index          => R,
            Ref_Line           => Ref_Line,
            Ref_Column         => Ref_Column,
            Ref_Visible_Column =>
              (if Ref_Visible_Column = -1
               then Visible_Column_Type (Ref_Column)
               else Ref_Visible_Column));
         Update_Location (Context, Buffer);
      end if;

      return Context;
   end Start;

   -----------
   -- Start --
   -----------

   overriding function Start
     (Self        : Regexp_Search;
      Buffer      : String;
      Start_Index : Integer := -1;
      End_Index   : Integer := -1;
      Ref_Index   : Integer := -1;
      Ref_Line    : Natural := 1;
      Ref_Column  : Character_Offset_Type := 1;
      Ref_Visible_Column : Visible_Column_Type := -1) return Search_Context
   is
      S : constant Integer :=
        (if Start_Index = -1 then Buffer'First else Start_Index);
      F : Integer := (if End_Index = -1 then Buffer'Last else End_Index);
      R : constant Integer :=
        (if Ref_Index = -1 then Buffer'First else Ref_Index);
      Context : Search_Context;
   begin
      --  Avoid an exception when calling Match
      if F = 0 then
         F := Positive'Last;
      end if;
      Match (Self.Pattern.all, Buffer, Self.Matches.all, S, F);

      --  The second test below works around an apparent bug in GNAT.Regpat

      if Self.Matches (0) = GNAT.Regpat.No_Match
        or else Self.Matches (0).First > Buffer'Last
      then
         if Self.Negate then
            Context := Search_Context'
              (Start              => S,
               Finish             => F,
               Line_Start         => 1,
               Line_End           => 1,
               Col_Start          => 1,
               Col_End            => 1,
               Col_Visible_Start  => 1,
               Col_Visible_End    => 1,
               Score              => 100,
               Buffer_Start       => S,
               Buffer_End         => F,
               Ref_Index          => R,
               Ref_Line           => Ref_Line,
               Ref_Column         => Ref_Column,
               Ref_Visible_Column =>
                 (if Ref_Visible_Column = -1
                  then Visible_Column_Type (Ref_Column)
                  else Ref_Visible_Column));

            Update_Location (Context, Buffer);
            return Context;
         else
            return No_Match;
         end if;
      elsif Self.Negate then
         return No_Match;
      end if;

      Context := Search_Context'
        (Start             => Self.Matches (0).First,
         Finish            => Self.Matches (0).Last,
         Line_Start        => 1,
         Line_End          => 1,
         Col_Start         => 1,
         Col_End           => 1,
         Col_Visible_Start => 1,
         Col_Visible_End   => 1,
         Score             => 100,
         Buffer_Start      => S,
         Buffer_End        => F,
         Ref_Index         => R,
         Ref_Line          => Ref_Line,
         Ref_Column        => Ref_Column,
         Ref_Visible_Column =>
           (if Ref_Visible_Column = -1
            then Visible_Column_Type (Ref_Column)
            else Ref_Visible_Column));

      Update_Location (Context, Buffer);
      return Context;
   end Start;

   -----------
   -- Start --
   -----------

   overriding function Start
     (Self        : Fuzzy_Search;
      Buffer      : String;
      Start_Index : Integer := -1;
      End_Index   : Integer := -1;
      Ref_Index   : Integer := -1;
      Ref_Line    : Natural := 1;
      Ref_Column  : Character_Offset_Type := 1;
      Ref_Visible_Column : Visible_Column_Type := -1) return Search_Context
   is
      S : constant Integer :=
        (if Start_Index = -1 then Buffer'First else Start_Index);
      F : constant Integer :=
        (if End_Index = -1 then Buffer'Last else End_Index);
      R : constant Integer :=
        (if Ref_Index = -1 then Buffer'First else Ref_Index);
      Start : Natural := Natural'Last;
      Score : Natural;

      T : Natural := Self.Text'First;
      Context : Search_Context;

      B : Natural := S;
      C, C2 : Unicode_Char;
      B1 : Natural;

   begin
      Utf8_Get_Char (Self.Text.all, T, C2);  --  also moves T to next char
      if not Self.Case_Sensitive then
         C2 := To_Lower (C2);
      end if;

      while B <= F loop
         B1 := B;
         Utf8_Get_Char (Buffer, B, C); --  also moves B to next char
         if not Self.Case_Sensitive then
            C := To_Lower (C);
         end if;

         if C = C2 then
            if Start = Natural'Last then
               Start := B1;
            end if;

            if T > Self.Text'Last then
               --  The score should be higher when the characters are closer
               --  together
               Score := 101 - (B - Start);

               if Self.Negate then
                  return GPS.Search.No_Match;
               else
                  Context := Search_Context'
                    (Start              => Start,
                     Finish             => B - 1,
                     Line_Start         => 1,
                     Line_End           => 1,
                     Col_Start          => 1,
                     Col_End            => 1,
                     Col_Visible_Start  => 1,
                     Col_Visible_End    => 1,
                     Score              => Score,
                     Buffer_Start       => S,
                     Buffer_End         => F,
                     Ref_Index          => R,
                     Ref_Line           => Ref_Line,
                     Ref_Column         => Ref_Column,
                     Ref_Visible_Column =>
                       (if Ref_Visible_Column = -1
                        then Visible_Column_Type (Ref_Column)
                        else Ref_Visible_Column));

                  Update_Location (Context, Buffer);
                  return Context;
               end if;
            end if;

            Utf8_Get_Char (Self.Text.all, T, C2);  --  moves T forward
            if not Self.Case_Sensitive then
               C2 := To_Lower (C2);
            end if;
         end if;
      end loop;

      if Self.Negate then
         Context := Search_Context'
           (Start              => S,
            Finish             => F,
            Line_Start         => 1,
            Line_End           => 1,
            Col_Start          => 1,
            Col_End            => 1,
            Col_Visible_Start  => 1,
            Col_Visible_End    => 1,
            Score              => Score,
            Buffer_Start       => S,
            Buffer_End         => F,
            Ref_Index          => R,
            Ref_Line           => Ref_Line,
            Ref_Column         => Ref_Column,
            Ref_Visible_Column =>
              (if Ref_Visible_Column = -1
               then Visible_Column_Type (Ref_Column)
               else Ref_Visible_Column));
         Update_Location (Context, Buffer);
         return Context;

      else
         return GPS.Search.No_Match;
      end if;
   end Start;

   -----------
   -- Start --
   -----------

   overriding function Start
     (Self        : Approximate_Search;
      Buffer      : String;
      Start_Index : Integer := -1;
      End_Index   : Integer := -1;
      Ref_Index   : Integer := -1;
      Ref_Line    : Natural := 1;
      Ref_Column  : Character_Offset_Type := 1;
      Ref_Visible_Column : Visible_Column_Type := -1) return Search_Context
   is
      S : constant Integer :=
        (if Start_Index = -1 then Buffer'First else Start_Index);
      F : constant Integer :=
        (if End_Index = -1 then Buffer'Last else End_Index);
      R : constant Integer :=
        (if Ref_Index = -1 then Buffer'First else Ref_Index);
      Context : Search_Context :=
        (Start             => S,  --  first byte of the matched substring
         Finish            => S - 1,   --  last byte of last char read
         Line_Start        => 1,
         Line_End          => 1,
         Col_Start         => 1,
         Col_End           => 1,
         Col_Visible_Start => 1,
         Col_Visible_End   => 1,
         Score             => 100,
         Buffer_Start      => S,
         Buffer_End        => F,
         Ref_Index         => R,
         Ref_Line          => Ref_Line,
         Ref_Column        => Ref_Column,
         Ref_Visible_Column =>
           (if Ref_Visible_Column = -1
            then Visible_Column_Type (Ref_Column)
            else Ref_Visible_Column));
   begin
      --  Initialize the pattern with K ones
      Self.Result.all := (others => 0);
      for K in 1 .. Self.Max_Errors loop
         Self.Result (K) := Shift_Left (Self.Result (K - 1), 1) or 1;
      end loop;

      Next (Self, Buffer, Context);

      if Context = No_Match and then Self.Negate then
         Context.Start := S;
         Context.Finish := F;
         return Context;
      elsif Self.Negate then
         return No_Match;
      else
         return Context;
      end if;
   end Start;

   ----------
   -- Next --
   ----------

   overriding procedure Next
     (Self    : Approximate_Search;
      Buffer  : String;
      Context : in out Search_Context)
   is
      C : Unicode_Char;
      P, P1 : Natural;
      Tmp_R : Approximate_Status;
      Offset : Mask;

   begin
      P := Context.Finish + 1;  --  points to first byte of first char

      while P <= Context.Buffer_End loop
         P1 := P;
         Utf8_Get_Char (Buffer, P, C);
         if not Self.Case_Sensitive then
            C := To_Lower (C);
         end if;

         Tmp_R := Self.Result.all;

         if C in Self.Pattern'Range then
            Offset := Self.Pattern (C);
         else
            Offset := 0;
         end if;

         Self.Result (0) := (Shift_Left (Tmp_R (0), 1) or 1) and Offset;

         for K in 1 .. Self.Max_Errors loop
            Self.Result (K) :=
              ((Shift_Left (Tmp_R (K), 1) or 1) and Offset)
              or (Shift_Left (Tmp_R (K - Approximate_Substitution_Cost)
                              or Self.Result (K - Approximate_Deletion_Cost),
                              1) or 1)
              or Tmp_R (K - Approximate_Insertion_Cost);
         end loop;

         for K in Self.Result'First .. Self.Max_Errors loop
            if P - Self.Text'Length - K + 1 >= Buffer'First
              and then (Self.Result (K) and Self.Matched) /= 0
            then
               Context.Start := P1;
               for N in 1 .. Utf8_Length (Self.Text.all) - 1 loop
                  Context.Start := Utf8_Prev_Char (Buffer, Context.Start);
               end loop;

--                 Context.Start := Integer'Max
--                   (Context.Buffer_Start, P1 - Self.Text'Length - K + 1);
               Context.Finish := P - 1;  --  last byte of last significant char

               Context.Score := 100 - K;
               Update_Location (Context, Buffer);
               return;
            end if;
         end loop;
      end loop;

      Context := No_Match;
   end Next;

   ----------
   -- Free --
   ----------

   overriding procedure Free (Self : in out Approximate_Search) is
      procedure Unchecked_Free is new Ada.Unchecked_Deallocation
        (Approximate_Status, Approximate_Status_Access);
      procedure Unchecked_Free is new Ada.Unchecked_Deallocation
        (Character_Mask_Array, Character_Masks);
   begin
      Unchecked_Free (Self.Pattern);
      Unchecked_Free (Self.Result);
   end Free;

   ----------
   -- Next --
   ----------

   overriding procedure Next
     (Self    : Fuzzy_Search;
      Buffer  : String;
      Context : in out Search_Context)
   is
      T : Natural := Self.Text'First;
      B : Natural := Context.Finish + 1;
      B1 : Natural;
      C, C2 : Unicode_Char;
   begin
      Utf8_Get_Char (Self.Text.all, T, C2);  --  moves T forward
      if not Self.Case_Sensitive then
         C2 := To_Lower (C2);
      end if;

      Context.Start := Natural'Last;

      while B <= Context.Buffer_End loop
         B1 := B;
         Utf8_Get_Char (Buffer, B, C);  --  moves B forward
         if not Self.Case_Sensitive then
            C := To_Lower (C);
         end if;

         if C = C2 then
            if Context.Start = Natural'Last then
               Context.Start := B1;
            end if;

            if T > Self.Text'Last then
               Context.Score := 101 - (B - Context.Start);
               Context.Finish := B - 1;
               Update_Location (Context, Buffer);
               return;
            end if;

            Utf8_Get_Char (Self.Text.all, T, C2);  --  moves T forward
            if not Self.Case_Sensitive then
               C2 := To_Lower (C2);
            end if;
         end if;
      end loop;
      Context := No_Match;
   end Next;

   ---------------------
   -- Highlight_Match --
   ---------------------

   overriding function Highlight_Match
      (Self    : Fuzzy_Search;
       Buffer  : String;
       Context : Search_Context) return String
   is
      T : Natural := Self.Text'First;
      Result : Unbounded_String;
      B : Natural := Context.Start;
      B1 : Natural;
      C, C2 : Unicode_Char;
   begin
      if not Self.Allow_Highlight
        or else Self.Negate
        or else Self.Text'Length = 0
      then
         return Buffer;
      end if;

      Utf8_Get_Char (Self.Text.all, T, C2); --  moves T forward
      if not Self.Case_Sensitive then
         C2 := To_Lower (C2);
      end if;

      Result := To_Unbounded_String
         (Glib.Convert.Escape_Text (Buffer (Buffer'First .. B - 1)));

      while B <= Context.Finish loop
         B1 := B;
         Utf8_Get_Char (Buffer, B, C);  --  moves B forward
         if not Self.Case_Sensitive then
            C := To_Lower (C);
         end if;

         if C2 /= Unicode_Char'Last and then C = C2 then
            Append (Result, "<b>"
                    & Glib.Convert.Escape_Text
                      ("" & Buffer (B1 .. B - 1)) & "</b>");

            if T <= Self.Text'Last then
               Utf8_Get_Char (Self.Text.all, T, C2); --  moves T forward
               if not Self.Case_Sensitive then
                  C2 := To_Lower (C2);
               end if;
            else
               C2 := Unicode_Char'Last;
            end if;
         else
            Append (Result, Glib.Convert.Escape_Text (Buffer (B1 .. B - 1)));
         end if;
      end loop;

      Append (Result, Glib.Convert.Escape_Text (Buffer (B .. Buffer'Last)));
      return To_String (Result);
   end Highlight_Match;

   ----------
   -- Next --
   ----------

   overriding procedure Next
     (Self    : Full_Text_Search;
      Buffer  : String;
      Context : in out Search_Context)
   is
      Index : Integer;
   begin
      Index := GNATCOLL.Boyer_Moore.Search
        (Self.Pattern.all, Buffer (Context.Start + 1 .. Context.Buffer_End));
      if Index = -1 then
         Context := No_Match;
      else
         Context.Start := Index;
         Context.Finish := Index + Self.Length - 1;
         Update_Location (Context, Buffer);
      end if;
   end Next;

   ----------
   -- Next --
   ----------

   overriding procedure Next
     (Self    : Regexp_Search;
      Buffer  : String;
      Context : in out Search_Context)
   is
   begin
      Match (Self.Pattern.all, Buffer, Self.Matches.all,
             Context.Start + 1, Context.Buffer_End);

      --  The second test below works around an apparent bug in GNAT.Regpat

      if Self.Matches (0) = GNAT.Regpat.No_Match
        or else Self.Matches (0).First > Buffer'Last
      then
         Context := No_Match;
      else
         Context.Start := Self.Matches (0).First;
         Context.Finish := Self.Matches (0).Last;
         Update_Location (Context, Buffer);
      end if;
   end Next;

   ---------------------
   -- Highlight_Match --
   ---------------------

   function Highlight_Match
      (Self    : Search_Pattern;
       Buffer  : String;
       Context : Search_Context) return String
   is
      B, F, S, E : Natural;
   begin
      if not Self.Allow_Highlight or else Self.Negate then
         return Buffer;
      end if;

      B := Integer'Max (Context.Buffer_Start, Buffer'First);
      F := Integer'Min (Context.Buffer_End, Buffer'Last);
      S := Integer'Max (Context.Start, Buffer'First);
      E := Integer'Min (Context.Finish, Buffer'Last);

      return Glib.Convert.Escape_Text (Buffer (B .. S - 1))
         & "<b>"
         & Glib.Convert.Escape_Text (Buffer (S .. E))
         & "</b>"
         & Glib.Convert.Escape_Text (Buffer (E + 1 .. F));
   end Highlight_Match;

   ----------
   -- Free --
   ----------

   procedure Free (Self : in out Search_Result) is
   begin
      Trace (Memcheck_Handle, "Free Search_Result");
      if Self.Id /= Self.Short and then Self.Id /= Self.Long then
         Free (Self.Id);
      end if;

      Free (Self.Short);
      Free (Self.Long);
   end Free;

   ----------
   -- Free --
   ----------

   procedure Free (Self : in out Search_Result_Access) is
      procedure Unchecked_Free is new Ada.Unchecked_Deallocation
        (Search_Result'Class, Search_Result_Access);
   begin
      if Self /= null then
         Free (Self.all);
         Unchecked_Free (Self);
      end if;
   end Free;

   ----------
   -- Free --
   ----------

   procedure Free (Self : in out Search_Provider_Access) is
      procedure Unchecked_Free is new Ada.Unchecked_Deallocation
        (Search_Provider'Class, Search_Provider_Access);
   begin
      if Self /= null then
         Free (Self.all);
         Unchecked_Free (Self);
      end if;
   end Free;

   --------------
   -- Register --
   --------------

   procedure Register
     (Self     : in out Search_Provider_Registry;
      Template : not null access Search_Provider'Class)
   is
   begin
      Self.Providers.Append
         ((Provider => Search_Provider_Access (Template)));
      Search_Provider_Registry'Class (Self).Sort_Providers;
   end Register;

   --------------------
   -- Sort_Providers --
   --------------------

   procedure Sort_Providers (Self : in out Search_Provider_Registry) is
   begin
      Sorting_By_Rank.Sort (Self.Providers);
   end Sort_Providers;

   ---------
   -- Get --
   ---------

   function Get
     (Self : Search_Provider_Registry;
      N    : Positive) return Search_Provider_Access
   is
      use Provider_Lists;
      C : Provider_Lists.Cursor;
      Count : Natural := 1;
   begin
      if N > Integer (Self.Providers.Length) then
         return null;
      else
         C := Self.Providers.First;
         while Has_Element (C)
            and then Count < N
         loop
            Count := Count + 1;
            Next (C);
         end loop;

         if Has_Element (C) then
            return Element (C).Provider;
         else
            return null;
         end if;
      end if;
   end Get;

   ---------
   -- Get --
   ---------

   function Get
     (Self : Search_Provider_Registry;
      Name : String) return Search_Provider_Access is
   begin
      for P of Self.Providers loop
         if P.Provider.Display_Name = Name then
            return P.Provider;
         end if;
      end loop;
      return null;
   end Get;

   ----------
   -- Free --
   ----------

   overriding procedure Free (Self : in out Full_Text_Search) is
      procedure Unchecked_Free is new Ada.Unchecked_Deallocation
        (GNATCOLL.Boyer_Moore.Pattern, Boyer_Moore_Pattern_Access);
   begin
      Free (Search_Pattern (Self));
      Unchecked_Free (Self.Pattern);
   end Free;

   ----------
   -- Free --
   ----------

   overriding procedure Free (Self : in out Regexp_Search) is
      procedure Unchecked_Free is new Ada.Unchecked_Deallocation
        (GNAT.Regpat.Match_Array, Match_Array_Access);
   begin
      Free (Search_Pattern (Self));
      Unchecked_Free (Self.Pattern);
      Unchecked_Free (Self.Matches);
   end Free;

   ----------
   -- Free --
   ----------

   procedure Free (Self : in out Search_Pattern_Access) is
      procedure Unchecked_Free is new Ada.Unchecked_Deallocation
        (Search_Pattern'Class, Search_Pattern_Access);
   begin
      if Self /= null then
         Free (Self.all);
         Unchecked_Free (Self);
      end if;
   end Free;

   -------------------------
   -- Compile_Approximate --
   -------------------------

   function Compile_Approximate
     (Pattern         : String;
      Case_Sensitive  : Boolean;
      Whole_Word      : Boolean;
      Allow_Highlight : Boolean;
      Negate          : Boolean) return Approximate_Search_Access
   is
      Result : constant Approximate_Search_Access := new Approximate_Search'
        (Text            => new String'(Pattern),
         Case_Sensitive  => Case_Sensitive,
         Whole_Word      => Whole_Word,
         Kind            => Approximate,
         Negate          => Negate,
         Pattern         => null,

         --  We want at least two characters of the pattern to match, otherwise
         --  it doesn't make sense.
         Max_Errors      => Integer'Max
           (0, Integer'Min (Approximate_Max_Errors, Pattern'Length - 1)),

         Result          => new Approximate_Status,
         Allow_Highlight => Allow_Highlight,
         Matched         =>  2 ** (Pattern'Length - 1));

      Min : Unicode_Char := Unicode_Char'Last;
      Max : Unicode_Char := 0;
      C : Unicode_Char;
      P : Natural := Pattern'First;
   begin
      while P <= Pattern'Last loop
         Utf8_Get_Char (Pattern, P, C);
         if not Case_Sensitive then
            C := To_Lower (C);
         end if;

         Min := Unicode_Char'Min (Min, C);
         Max := Unicode_Char'Max (Max, C);
      end loop;

      Result.Pattern := new Character_Mask_Array (Min .. Max);
      Result.Pattern.all := (others => 0);

      --  Compared to the paper, we revert the bit ordering in S
      P := Pattern'First;
      while P <= Pattern'Last loop
         Utf8_Get_Char (Pattern, P, C);
         if not Case_Sensitive then
            C := To_Lower (C);
         end if;

         Result.Pattern (C) :=
           Result.Pattern (C) or 2 ** (P - 1 - Pattern'First);
      end loop;

      return Result;
   end Compile_Approximate;

   -----------
   -- Build --
   -----------

   function Build
     (Pattern         : String;
      Case_Sensitive  : Boolean := False;
      Whole_Word      : Boolean := False;
      Negate          : Boolean := False;
      Kind            : Search_Kind := Full_Text;
      Allow_Highlight : Boolean := False)
      return Search_Pattern_Access
   is
      BM    : Boyer_Moore_Pattern_Access;
      Re    : GNAT.Expect.Pattern_Matcher_Access;
      Flags : Regexp_Flags := Multiple_Lines;
      WD    : constant String := "\b";  --  word delimiter
   begin
      case Kind is
         when Full_Text =>
            BM := new GNATCOLL.Boyer_Moore.Pattern;
            Compile (BM.all, Pattern, Case_Sensitive => Case_Sensitive);
            return new Full_Text_Search'
              (Pattern         => BM,
               Text            => new String'(Pattern),
               Case_Sensitive  => Case_Sensitive,
               Negate          => Negate,
               Allow_Highlight => Allow_Highlight,
               Whole_Word      => Whole_Word,
               Kind            => Kind,
               Length          => Pattern'Length);

         when Fuzzy =>
            return new Fuzzy_Search'
              (Text            => new String'(Pattern),
               Allow_Highlight => Allow_Highlight,
               Case_Sensitive  => Case_Sensitive,
               Whole_Word      => Whole_Word,
               Negate          => Negate,
               Kind            => Kind);

         when Approximate =>
            if Pattern'Length > 64 then
               --  Fallback to Full_Text, pattern is too long
               BM := new GNATCOLL.Boyer_Moore.Pattern;
               Compile (BM.all, Pattern, Case_Sensitive => Case_Sensitive);
               return new Full_Text_Search'
                 (Pattern         => BM,
                  Text            => new String'(Pattern),
                  Allow_Highlight => Allow_Highlight,
                  Case_Sensitive  => Case_Sensitive,
                  Whole_Word      => Whole_Word,
                  Kind            => Kind,
                  Negate          => Negate,
                  Length          => Pattern'Length);

            else
               return Search_Pattern_Access (Compile_Approximate
                 (Pattern,
                  Allow_Highlight => Allow_Highlight,
                  Case_Sensitive  => Case_Sensitive,
                  Negate          => Negate,
                  Whole_Word      => Whole_Word));
            end if;

         when Regexp =>
            if not Case_Sensitive then
               Flags := Flags or Case_Insensitive;
            end if;

            begin
               if Whole_Word then
                  Re := new GNAT.Regpat.Pattern_Matcher'
                    (Compile (WD & Pattern & WD, Flags));
               else
                  Re := new GNAT.Regpat.Pattern_Matcher'
                    (Compile (Pattern, Flags));
               end if;

               return new Regexp_Search'
                 (Pattern        => Re,
                  Text           => new String'(Pattern),
                  Allow_Highlight => False,
                  Case_Sensitive => Case_Sensitive,
                  Whole_Word     => Whole_Word,
                  Kind           => Kind,
                  Negate         => Negate,
                  Matches      => new Match_Array (0 .. Paren_Count (Re.all)));

            exception
               when GNAT.Regpat.Expression_Error =>
                  return Build
                    (Pattern         => Pattern,
                     Case_Sensitive  => Case_Sensitive,
                     Whole_Word      => Whole_Word,
                     Kind            => Full_Text,
                     Negate          => Negate,
                     Allow_Highlight => Allow_Highlight);
            end;
      end case;
   end Build;

   -----------
   -- Build --
   -----------

   function Build
      (Pattern : not null access Search_Pattern'Class;
       Text    : String) return Search_Pattern_Access is
   begin
      return Build
         (Pattern         => Text,
          Case_Sensitive  => Pattern.Case_Sensitive,
          Allow_Highlight => Pattern.Allow_Highlight,
          Whole_Word      => Pattern.Whole_Word,
          Negate          => Pattern.Negate,
          Kind            => Pattern.Kind);
   end Build;

   -----------
   -- Build --
   -----------

   function Build
      (Pattern : not null access Search_Pattern'Class;
       Kind    : Search_Kind) return Search_Pattern_Access is
   begin
      return Build
         (Pattern         => Pattern.Text.all,
          Case_Sensitive  => Pattern.Case_Sensitive,
          Whole_Word      => Pattern.Whole_Word,
          Allow_Highlight => Pattern.Allow_Highlight,
          Negate          => Pattern.Negate,
          Kind            => Kind);
   end Build;

   ----------------
   -- Get_Negate --
   ----------------

   function Get_Negate
     (Pattern : not null access Search_Pattern'Class) return Boolean is
   begin
      return Pattern.Negate;
   end Get_Negate;

   ------------------------
   -- Get_Case_Sensitive --
   ------------------------

   function Get_Case_Sensitive
     (Pattern    : not null access Search_Pattern'Class) return Boolean is
   begin
      return Pattern.Case_Sensitive;
   end Get_Case_Sensitive;

   --------------------
   -- Get_Whole_Word --
   --------------------

   function Get_Whole_Word
     (Pattern    : not null access Search_Pattern'Class) return Boolean is
   begin
      return Pattern.Whole_Word;
   end Get_Whole_Word;

   --------------
   -- Get_Kind --
   --------------

   function Get_Kind
      (Pattern : not null access Search_Pattern'Class) return Search_Kind is
   begin
      return Pattern.Kind;
   end Get_Kind;

   --------------
   -- Get_Text --
   --------------

   function Get_Text
      (Pattern : not null access Search_Pattern'Class) return String is
   begin
      return Pattern.Text.all;
   end Get_Text;

   ----------
   -- Free --
   ----------

   procedure Free (Self : in out Search_Pattern) is
   begin
      Free (Self.Text);
   end Free;

   ---------
   -- "=" --
   ---------

   overriding function "=" (P1, P2 : Search_Pattern) return Boolean is
   begin
      if P1.Text = null or else P2.Text = null then
         return False;
      end if;
      return P1.Text.all = P2.Text.all;
   end "=";

   ------------
   -- Equals --
   ------------

   function Equals
     (P1, P2 : Search_Pattern_Access) return Boolean is
   begin
      if P1 = null then
         return P2 = null;
      elsif P2 = null then
         return False;
      else
         return P1.all = P2.all;
      end if;
   end Equals;

   --------------------
   -- Compute_Suffix --
   --------------------

   procedure Compute_Suffix
     (Self        : Search_Pattern;
      Context     : Search_Context;
      Text        : String;
      Suffix      : in out Ada.Strings.Unbounded.Unbounded_String;
      Suffix_Last : in out Natural)
   is
      T : constant String := To_String (Suffix);
   begin
      if T = "" then
         Suffix := To_Unbounded_String
           (Text (Context.Finish + 1 .. Text'Last));
         Suffix_Last := Length (Suffix);
      else
         for S in 1 .. Suffix_Last loop
            if Context.Finish + S > Text'Last then
               Suffix_Last := S - 1;
               exit;
            else
               if (Self.Case_Sensitive
                   and then T (S) /= Text (Context.Finish + S))
                 or else
                   (not Self.Case_Sensitive
                    and then To_Lower (T (S)) /=
                      To_Lower (Text (Context.Finish + S)))
               then
                  Suffix_Last := S - 1;
                  exit;
               end if;
            end if;
         end loop;

         if Suffix_Last = 0 then
            Trace (Me, "No suffix completion, previous candidate was "
                   & T & " and new attempt was " & Text);
         end if;
      end if;
   end Compute_Suffix;

   --------------------------
   -- Get_Allow_Highlights --
   --------------------------

   function Get_Allow_Highlights
     (Self  : not null access Search_Pattern'Class) return Boolean is
   begin
      return Self.Allow_Highlight;
   end Get_Allow_Highlights;

end GPS.Search;
