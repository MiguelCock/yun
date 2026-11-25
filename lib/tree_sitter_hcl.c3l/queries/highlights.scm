(comment) @comment
(string_lit) @string
(quoted_template) @string
(heredoc_template) @string
(numeric_lit) @number
(bool_lit) @boolean
(null_lit) @constant.builtin
(attribute (identifier) @property)
(block (identifier) @type)
(function_call (identifier) @function)
(get_attr (identifier) @property)
