open Types

let filenameR = {|File "(.+)"|}
let lineR = {|File .+, line (\d+)|}
let chars1R = {|File .+, characters (\d+)|}
let chars2R = {|File .+, characters .+-(\d+)|}

(* helpers for getting the first (presumably only) match in a string *)
let get_match pat str = Pcre.get_substring (Pcre.exec ~pat:pat str) 1
let get_match_maybe pat str =
  try Some (Pcre.get_substring (Pcre.exec ~pat:pat str) 1)
  with Not_found -> None
(* helper for turning Not_found exception into an optional *)
let exec ~rex str = try Some (Pcre.exec ~rex str) with Not_found -> None

let split sep str = Pcre.split ~pat:sep str

(* agnostic extractors, turning err string into proper data structures *)
let type_MismatchTypeArguments err errLines =
  (* let filename = get_match filenameR err in
  let line = get_match lineR err in
  let chars1 = get_match chars1R err in
  let chars2 = get_match chars2R err in *)
  (* let regex = {|Error: The type constructor\s*([\w\.]*)\s*expects[\s]*(\d+)\s*argument\(s\),\s*but is here applied to\s*(\d+)\s*argument\(s\)|} in *)
    Type_MismatchTypeArguments {
      constructor = "asd";
      expectedCount = 1;
      observedCount = 2;
    }
    (* Type_MismatchTypeArguments (
      filename ^ " " ^ line ^ ":" ^ chars1 ^ "-" ^ chars2 ^ "\n" ^
      (List.nth fileLines ((int_of_string line) - 1)) ^ "\n" ^
      (String.make (int_of_string chars1) ' ') ^
      (String.make ((int_of_string chars2) - (int_of_string chars1)) '^') ^ "\n" ^
      String.concat "\n" (List.tl errLines)
    ) *)

let type_UnboundValue err errLines = raise Not_found
let type_SignatureMismatch err errLines = raise Not_found
let type_SignatureItemMissing err errLines = raise Not_found
let type_UnboundModule err errLines = raise Not_found
let type_UnboundRecordField err errLines = raise Not_found
let type_UnboundConstructor err errLines = raise Not_found

let type_UnboundTypeConstructor err errLines =
  let filename = get_match filenameR err in
  let line = int_of_string (get_match lineR err) in
  let chars1 = int_of_string (get_match chars1R err) in
  let chars2 = int_of_string (get_match chars2R err) in

  let constructorR = {|Error: Unbound type constructor (.+)|} in
  let constructor = get_match constructorR err in
  let suggestionR = {|Hint: Did you mean (.+)\?|} in
  let suggestion = get_match_maybe suggestionR err in
    Type_UnboundTypeConstructor {
      fileInfo = {
        content = Batteries.List.of_enum (BatFile.lines_of filename);
        name = filename;
        line = line;
        cols = (chars1, chars2);
      };
      namespacedConstructor = constructor;
      suggestion = suggestion
    }

(* need: number of arguments actually applied to it, and what they are *)
(* need: number of args the function asks, and what types they are *)
let type_AppliedTooMany err errLines =
  let filename = get_match filenameR err in
  let line = int_of_string (get_match lineR err) in
  let chars1 = int_of_string (get_match chars1R err) in
  let chars2 = int_of_string (get_match chars2R err) in

  let functionTypeR = {|This function has type (.+)\n +It is applied to too many arguments; maybe you forgot a `;'.|} in
  let functionType = get_match functionTypeR err in
  (* the func type 'a -> (int -> 'b) -> string has 2 arguments *)
  (* strip out false positive -> from nested function types passed as param *)
  let nestedFunctionTypeR = {|\(.+\)|} in
  let cleaned = Pcre.replace ~pat:nestedFunctionTypeR ~templ:"bla" functionType in
  let expectedArgCount = List.length (split "->" cleaned) - 1 in
    Type_AppliedTooMany {
      fileInfo = {
        content = Batteries.List.of_enum (BatFile.lines_of filename);
        name = filename;
        line = line;
        cols = (chars1, chars2);
      };
      functionType = functionType;
      expectedArgCount = expectedArgCount;
    }

let type_RecordFieldNotInExpression err errLines = raise Not_found
let type_RecordFieldError err errLines = raise Not_found
let type_FieldNotBelong err errLines = raise Not_found

(* need: where the original expected comes from  *)
let type_IncompatibleType err errLines =
  let filename = get_match filenameR err in
  let line = int_of_string (get_match lineR err) in
  let chars1 = int_of_string (get_match chars1R err) in
  let chars2 = int_of_string (get_match chars2R err) in

  (* the type actual and expected might be on their own line *)
  let actualR = {|Error: This expression has type([\s\S]*?)but an expression was expected of type|} in
  let expectedR = {|Error: This expression has type[\s\S]*?but an expression was expected of type([\s\S]*?)$|} in
  let actual = get_match actualR err |> BatString.trim in
  let expected = get_match expectedR err |> BatString.trim in
    Type_IncompatibleType {
      fileInfo = {
        content = Batteries.List.of_enum (BatFile.lines_of filename);
        name = filename;
        line = line;
        cols = (chars1, chars2);
      };
      actual = actual;
      expected = expected;
    }

let type_NotAFunction err errLines =
  let filename = get_match filenameR err in
  let line = int_of_string (get_match lineR err) in
  let chars1 = int_of_string (get_match chars1R err) in
  let chars2 = int_of_string (get_match chars2R err) in

  let actualR = {|This expression has type (.+)\n +This is not a function; it cannot be applied.|} in
  let actual = get_match actualR err in
    Type_NotAFunction {
      fileInfo = {
        content = Batteries.List.of_enum (BatFile.lines_of filename);
        name = filename;
        line = line;
        cols = (chars1, chars2);
      };
      actual = actual;
    }

(* TODO: apparently syntax error can be followed by more indications *)
(* need: way, way more information, I can't even *)
let file_SyntaxError err errLines =
  let filename = get_match filenameR err in
  let line = int_of_string (get_match lineR err) in
  let chars1 = int_of_string (get_match chars1R err) in
  let chars2 = int_of_string (get_match chars2R err) in

  let fieldR = {|Error: Syntax error|} in
  let fileLines = Batteries.List.of_enum (BatFile.lines_of filename) in
   (* some syntax errors will make the output point at the last line + 1, char
   0-0, to indicate e.g. "there's something missing at the end here". Ofc that
   isn't a valid location to point to in a reporter *)
  let passedBoundary = List.length fileLines = line - 1 in
    (* raise the same error than if we failed to match *)
    if not (Pcre.pmatch ~pat:fieldR err) then raise Not_found
    else File_SyntaxError {
      fileInfo = {
        content = Batteries.List.of_enum (BatFile.lines_of filename);
        name = filename;
        line = if passedBoundary then line - 1 else line;
        cols = (chars1, if passedBoundary then chars2 + 1 else chars2);
      };
    }

let build_InconsistentAssumptions err errLines = raise Not_found
let warning_CatchAll err errLines = raise Not_found
let warning_UnusedVariable err errLines = raise Not_found

let warning_PatternNotExhaustive err errLines =
  let filename = get_match filenameR err in
  let line = int_of_string (get_match lineR err) in
  let chars1 = int_of_string (get_match chars1R err) in
  (* let chars2 = int_of_string (get_match chars2R err) in *)

  let unmatchedR = {|Warning 8: this pattern-matching is not exhaustive.\nHere is an example of a value that is not matched:\n(.+)|} in
  let unmatchedRaw = get_match unmatchedR err in
  (* ocaml has a bug/feature where it'll show that the range of the error for
  the variant is from the first letter of "match bla with ..." to the end of the
  whole pattern block, **as if the code was written on a single line**. This
  might be because their file line reporting got too rigid and can't show you
  line range. But for us it's pretty useless so we limit it to just highlight
  the word match *)
  let unmatched = if (BatString.get unmatchedRaw 0) = '(' then
    (* format was (Variant1|Variant2|Variant3). We strip the surrounding parens *)
    BatString.sub unmatchedRaw 1 (BatString.length unmatchedRaw - 2) |> split {|\||}
  else
    [unmatchedRaw]
  in

  Warning_PatternNotExhaustive {
    fileInfo = {
      content = Batteries.List.of_enum (BatFile.lines_of filename);
      name = filename;
      line = line;
      cols = (chars1, chars1 + 5);
    };
    unmatched = unmatched;
    warningCode = 8;
  }

let warning_PatternUnused err errLines = raise Not_found
let warning_OptionalArgumentNotErased err errLines = raise Not_found

(* need: list of legal characters *)
let file_IllegalCharacter err errLines =
  let filename = get_match filenameR err in
  let line = int_of_string (get_match lineR err) in
  let chars1 = int_of_string (get_match chars1R err) in
  let chars2 = int_of_string (get_match chars2R err) in

  let characterR = {|Error: Illegal character \((.+)\)|} in
  let character = get_match characterR err in
    File_IllegalCharacter {
      fileInfo = {
        content = Batteries.List.of_enum (BatFile.lines_of filename);
        name = filename;
        line = line;
        cols = (chars1, chars2);
      };
      character = character;
    }

let unparsable err errLines = Unparsable err

let parsers = [
  (* type_MismatchTypeArguments; *)
  type_UnboundValue;
  type_SignatureMismatch;
  type_SignatureItemMissing;
  type_UnboundModule;
  type_UnboundRecordField;
  type_UnboundConstructor;
  type_UnboundTypeConstructor;
  type_AppliedTooMany;
  type_RecordFieldNotInExpression;
  type_RecordFieldError;
  type_FieldNotBelong;
  type_IncompatibleType;
  type_NotAFunction;
  file_SyntaxError;
  build_InconsistentAssumptions;
  warning_CatchAll;
  warning_UnusedVariable;
  warning_PatternNotExhaustive;
  warning_PatternUnused;
  warning_OptionalArgumentNotErased;
  file_IllegalCharacter;
  (* this should stay at last position. It's a catch-all that doesn't throw *)
  unparsable;
]

(* entry point, for convenience purposes for now. Theoretically the parser and
the reporters are decoupled *)
let () =
  try
    let err = BatPervasives.input_all stdin in
    let errLines = split "\n" err in
      let matched = BatList.find_map (fun f ->
        try Some (f err errLines) with Not_found -> None
      ) parsers in Reporter.print matched
  with BatIO.No_more_input -> print_endline "All good!"
