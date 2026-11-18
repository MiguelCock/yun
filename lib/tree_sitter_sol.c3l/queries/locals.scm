(function_declaration name: (identifier) @definition.function)
(operator_function_declaration name: (operator_symbol) @definition.function)
(struct_declaration name: (type_identifier) @definition.type)
(enum_declaration name: (type_identifier) @definition.type)
(fault_declaration name: (type_identifier) @definition.type)
(interface_declaration name: (type_identifier) @definition.type)
(protocol_declaration name: (type_identifier) @definition.type)
(impl_declaration type: (type_identifier) @definition.type)

(single_parameter name: (identifier) @definition.parameter)
(grouped_parameter name: (identifier) @definition.parameter)
(let_statement name: (identifier) @definition.var)
(typed_let_statement name: (identifier) @definition.var)
(for_statement binding: (identifier) @definition.var)
(for_borrow_statement binding: (identifier) @definition.var)
(catch_statement binding: (identifier) @definition.var)
(alias_statement (alias_name) @definition.var)

(block) @scope
(identifier) @reference
