(function_declaration) @function.outer
(function_declaration body: (block) @function.inner)
(operator_function_declaration) @function.outer
(operator_function_declaration body: (block) @function.inner)
(struct_declaration) @class.outer
(struct_declaration body: (field_list) @class.inner)
(enum_declaration) @class.outer
(interface_declaration) @class.outer
(protocol_declaration) @class.outer
(impl_declaration) @class.outer
(block) @block.outer
(comment) @comment.outer
