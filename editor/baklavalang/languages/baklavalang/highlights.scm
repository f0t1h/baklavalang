; Keywords
"if" @keyword
"else" @keyword
"let" @keyword
(halt) @keyword
"main" @keyword

; Booleans
(boolean) @constant.builtin

; Comments
(comment) @comment

; Strings
(string) @string

; Numbers
(number) @number

; Grid definition name
(grid_definition name: (identifier) @function.definition)

; Module calls
(module_call module: (module_name) @type)
(module_call function: (identifier) @function)
(erlang_module_call module: (erlang_module) @type)
(erlang_module_call function: (identifier) @function)
(function_call function: (identifier) @function)

; Data flow
(flow_operator) @operator
(hash) @keyword.special
"$" @keyword.special
"=>" @operator

; Operators
"+" @operator
"-" @operator
"*" @operator
"/" @operator
"==" @operator
"!=" @operator
"<" @operator
">" @operator
"<=" @operator
">=" @operator
"=" @operator

; Patterns
(wildcard_pattern) @variable.builtin
(pattern_identifier) @variable.parameter

; Identifiers (general, lower priority)
(identifier) @variable

; Punctuation
"[" @punctuation.bracket
"]" @punctuation.bracket
"{" @punctuation.bracket
"}" @punctuation.bracket
"(" @punctuation.bracket
")" @punctuation.bracket
"," @punctuation.delimiter
"|" @punctuation.delimiter
"." @punctuation.delimiter
":" @punctuation.delimiter

; Main section
(grid_ref (identifier) @function)
(relay_symbol) @string.special
(empty_cell) @comment
