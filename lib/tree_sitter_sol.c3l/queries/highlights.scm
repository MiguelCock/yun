; SOL syntax highlighting.

(comment) @comment
((comment) @comment.documentation
 (#match? @comment.documentation "^///|^//!"))

[
  "module" "import" "pub" "struct" "enum" "fault" "interface" "protocol"
  "impl" "extern" "for" "in" "if" "else" "match" "return"
  "catch" "defer" "spawn" "scope" "unsafe" "where" "true" "false"
] @keyword

(break_statement) @keyword
(continue_statement) @keyword
(none_literal) @constant.builtin

"some" @keyword.function

(module_declaration (module_path) @module)
(import_declaration (import_item (module_path) @module))

(struct_declaration name: (type_identifier) @type)
(enum_declaration name: (type_identifier) @type)
(fault_declaration name: (type_identifier) @type)
(interface_declaration name: (type_identifier) @type)
(protocol_declaration name: (type_identifier) @type)
(impl_declaration type: (type_identifier) @type)
(impl_declaration interface: (type_path) @type)

(function_declaration name: (identifier) @function)
(operator_function_declaration name: (operator_symbol) @function)
(method_signature name: (function_name) @function.method)
(extern_function name: (function_name) @function)

(call_expression function: (primary_expression (identifier) @function.call))
(call_expression function: (primary_expression (path) @function.call))
(pipe_target (path) @function.call)

(field name: (identifier) @property)
(struct_field name: (identifier) @property)
(enum_variant name: (member_name) @constructor)
(dot_variant (member_name) @constructor)
(struct_literal type: (type_path) @type)

(single_parameter name: (identifier) @variable.parameter)
(grouped_parameter name: (identifier) @variable.parameter)
(let_statement name: (identifier) @variable)
(typed_let_statement name: (identifier) @variable)
(for_statement binding: (identifier) @variable)
(for_borrow_statement binding: (identifier) @variable)
(catch_statement binding: (identifier) @variable)
(alias_name) @variable
(hash_parameter) @variable.parameter

(type_identifier) @type
(primitive_type) @type.builtin
(generic_parameter) @type.parameter

(decorator (path) @attribute)
(norecurse) @attribute

[
  "|>" "??" "->" ":=" "::" "=" "+=" "-=" "*=" "/=" "%=" ".="
  "+" "-" "*" "/" "%" "==" "!=" "<" "<=" ">" ">="
  "&&" "||" "and" "or" "|" "&" "^" "<<" ">>" "..<" "..="
  ".*" ".+" ".-" "./" ".%" ".==" ".!=" ".<" ".<=" ".>" ".>="
] @operator

[
  "(" ")" "[" "]" "{" "}" "," ":" "." "!"
  "?" "~"
] @punctuation.delimiter

(string) @string
(int_literal) @number
(float_literal) @number.float
(bool_literal) @constant.builtin
(none_literal) @constant.builtin

(ERROR) @error
