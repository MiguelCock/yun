module.exports = grammar({
  name: 'sol',

  extras: $ => [/\s/, $.comment, $.block_comment],
  word: $ => $.identifier,

  conflicts: $ => [
    [$.operator_function_declaration],
    [$.array_type, $.type_path],
    [$.primary_expression, $.struct_literal],
    [$.generic_parameter, $.primitive_type],
    [$.field_pattern],
    [$.const_declaration],
    [$.primary_expression, $.integer_literal],
    [$._type_atom, $.generic_type],
    [$.type],
    [$.pipe_target],
    [$.scope_expression],
    [$.decorator],
    [$.function_declaration],
    [$.primary_expression, $.path],
    [$.import_item],
    [$.return_statement],
    [$._statement, $.primary_expression],
  ],

  rules: {
    source_file: $ => seq(optional($.module_declaration), repeat($._top_item)),

    _top_item: $ => choice(
      $.import_declaration,
      $.macro_declaration,
      $.decorated_declaration,
      $._declaration,
    ),

    comment: $ => token(seq('//', /.*/)),
    block_comment: $ => token(seq('/*', /[^*]*\*+([^/*][^*]*\*+)*/, '/')),

    import_declaration: $ => seq('import', commaSep1($.import_item)),
    import_item: $ => seq($.module_path, optional($.norecurse)),
    norecurse: $ => seq('@', 'norecurse'),

    module_declaration: $ => seq('module', field('path', $.module_path)),
    module_path: $ => seq($.identifier, repeat(seq('::', $.identifier))),

    decorated_declaration: $ => prec(1, seq(repeat1($.decorator), $._declaration)),
    decorator: $ => seq('@', $.path, optional($.arguments)),

    _declaration: $ => choice(
      $.struct_declaration,
      $.enum_declaration,
      $.fault_declaration,
      $.interface_declaration,
      $.protocol_declaration,
      $.impl_declaration,
      $.extern_block,
      $.operator_function_declaration,
      $.function_declaration,
      $.const_declaration,
    ),

    struct_declaration: $ => prec(5, seq(
      optional('pub'),
      field('name', $.type_identifier), '::', token(prec(10, 'struct')),
      optional($.generic_parameters),
      field('body', $.field_list),
    )),

    field_list: $ => seq('{', repeat($.field), '}'),
    field: $ => seq(
      repeat($.decorator),
      optional('pub'),
      field('name', $.identifier), ':', field('type', $.type),
      optional(','),
    ),

    generic_parameters: $ => seq('(', commaSep1($.generic_parameter), optional(',') , ')'),
    generic_parameter: $ => seq(
      $._compile_time_name,
      ':',
      choice('type', 'usize', 'u32', 'i32', $.type),
    ),

    enum_declaration: $ => prec(5, seq(
      optional('pub'),
      field('name', $.type_identifier), '::', 'enum', '{',
      repeat($.enum_variant), '}',
    )),
    enum_variant: $ => seq(
      repeat($.decorator),
      optional('pub'),
      field('name', $.member_name),
      optional(choice($.field_list, $.tuple_payload)),
      optional(','),
    ),
    tuple_payload: $ => seq('(', commaSep($.type), optional(','), ')'),

    fault_declaration: $ => prec(5, seq(optional('pub'), field('name', $.type_identifier), '::', 'fault')),

    interface_declaration: $ => prec(5, seq(
      optional('pub'),
      field('name', $.type_identifier), '::', 'interface', '{',
      repeat($.method_signature), '}',
    )),
    protocol_declaration: $ => prec(5, seq(
      optional('pub'),
      field('name', $.type_identifier), '::', 'protocol', '{',
      repeat($.method_signature), '}',
    )),
    method_signature: $ => seq(
      repeat($.decorator),
      field('name', $.function_name),
      '::', $.parameters,
      optional(seq('->', $.type)),
      optional($.where_clause),
    ),

    impl_declaration: $ => prec(5, seq(
      field('type', $.type_identifier), '::', 'impl', field('interface', $.type_path), '{',
      repeat(choice($.function_declaration, $.operator_function_declaration)), '}',
    )),

    extern_block: $ => prec(5, seq(
      'extern', field('abi', $.string), '{',
      repeat($.extern_function), '}',
    )),
    extern_function: $ => seq(
      repeat($.decorator),
      field('name', $.function_name), '::', $.parameters,
      optional(seq('->', $.type)),
    ),

    function_declaration: $ => prec(5, seq(
      repeat($.decorator),
      optional('pub'),
      field('name', $.identifier),
      '::', $.parameters,
      optional(seq('->', $.type)),
      optional($.where_clause),
      field('body', $.block),
    )),

    operator_function_declaration: $ => prec(20, seq(
      repeat($.decorator),
      optional('pub'),
      field('name', $.operator_symbol),
      '::', $.parameters,
      optional(seq('->', $.type)),
      optional($.where_clause),
      field('body', $.block),
    )),

    const_declaration: $ => prec(1, seq(
      repeat($.decorator),
      optional('pub'),
      field('name', choice($.identifier, $.type_identifier)), '::',
      choice(
        seq(field('type', $.const_type), '=', field('value', $._expression)),
        field('value', choice($.int_literal, $.float_literal, $.string_literal, $.array_literal)),
      ),
    )),

    parameters: $ => seq('(', commaSep($.parameter), optional(','), ')'),
    parameter: $ => choice($.grouped_parameter, $.single_parameter),
    single_parameter: $ => seq(
      repeat($.decorator),
      optional($.convention),
      field('name', $.identifier), ':', field('type', choice($.type, $.alias_name)),
    ),
    grouped_parameter: $ => seq(
      repeat($.decorator),
      optional($.convention),
      field('name', $.identifier),
      repeat1(seq(',', field('name', $.identifier))),
      ':', field('type', choice($.type, $.alias_name)),
    ),
    convention: $ => choice('*', '&', '^'),

    where_clause: $ => seq('where', commaSep1($.where_constraint)),
    where_constraint: $ => seq($._compile_time_name, ':', $.type_path),

    block: $ => seq('{', repeat($._statement), '}'),
    _statement: $ => choice(
      $.let_statement,
      $.typed_let_statement,
      $.alias_statement,
      $.return_statement,
      $.break_statement,
      $.continue_statement,
      $.if_statement,
      $.for_statement,
      $.for_borrow_statement,
      $.for_condition,
      $.catch_statement,
      $.spawn_statement,
      $.defer_statement,
      $.macro_call_statement,
      $.assignment_statement,
      $.expression_statement,
      $.block,
    ),

    let_statement: $ => seq(field('name', $.identifier), ':=', field('value', $._expression)),
    typed_let_statement: $ => seq(
      field('name', $.identifier), ':', field('type', $.type),
      optional(seq('=', field('value', $._expression))),
    ),
    alias_statement: $ => seq($.alias_name, '::', field('value', $._expression)),
    return_statement: $ => seq('return', optional($._expression)),
    break_statement: $ => 'break',
    continue_statement: $ => 'continue',
    if_statement: $ => seq(
      'if', field('condition', $._expression), field('body', $.block),
      optional(seq('else', choice($.block, $.if_statement))),
    ),
    for_statement: $ => prec(5, seq(
      'for', optional($.convention), field('binding', $.identifier),
      'in', field('iterable', $._expression), field('body', $.block),
    )),
    for_borrow_statement: $ => prec(20, seq(
      'for', field('convention', choice('*', '&', '^')), field('binding', $.identifier),
      'in', field('iterable', $._expression), field('body', $.block),
    )),
    for_condition: $ => prec(1, seq('for', field('condition', $._expression), field('body', $.block))),
    catch_statement: $ => seq(
      'catch', field('binding', choice($.identifier, $._wildcard)),
      'in', field('value', $._expression), field('body', $.block),
    ),
    spawn_statement: $ => seq('spawn', field('call', $._expression)),
    defer_statement: $ => seq('defer', $.block),
    macro_call_statement: $ => seq($.decorator),
    assignment_statement: $ => seq(
      field('target', $._expression), $.assignment_operator, field('value', $._expression),
    ),
    assignment_operator: $ => choice('=', '+=', '-=', '*=', '/=', '%=', '.='),
    expression_statement: $ => $._expression,

    _expression: $ => choice(
      $.pipe_expression,
      $.coalesce_expression,
      $.binary_expression,
      $.unary_expression,
      $.postfix_expression,
      $.primary_expression,
    ),

    pipe_expression: $ => prec.left(1, seq(
      field('value', $._expression), '|>', field('target', $.pipe_target),
    )),
    pipe_target: $ => seq(
      $.path, optional($.arguments), optional($.pipe_postfix),
    ),
    pipe_postfix: $ => choice('!', '?'),

    coalesce_expression: $ => prec.right(2, seq(
      field('left', $._expression), '??', field('right', $._expression),
    )),

    binary_expression: $ => {
      const table = [
        [3, choice('||', 'or')],
        [4, choice('&&', 'and')],
        [5, '|'],
        [6, '^'],
        [7, '&'],
        [8, choice('==', '!=')],
        [9, choice('<', '<=', '>', '>=')],
        [10, choice('..<', '..=')],
        [11, choice('<<', '>>')],
        [12, choice('+', '-')],
        [13, choice('*', '/', '%')],
        [1, choice('.*', '.+', '.-', './', '.%', '.==', '.!=', '.<', '.<=', '.>', '.>=')],
      ];
      return choice(...table.map(([precedence, operator]) =>
        prec.left(precedence, seq(
          field('left', $._expression), field('operator', operator), field('right', $._expression),
        ))
      ));
    },

    unary_expression: $ => prec(14, seq(
      field('operator', choice('*', '&', '^', '-', '!', 'not', '~')), field('operand', $._expression),
    )),

    postfix_expression: $ => prec(15, seq(
      field('value', $._expression), field('operator', choice('!', '?', '~')),
    )),

    primary_expression: $ => choice(
      $.int_literal,
      $.float_literal,
      $.string_literal,
      $.bool_literal,
      $.unit_literal,
      $.none_literal,
      $.some_expression,
      $.identifier,
      $.alias_name,
      $.dot_variant,
      $.path,
      $.type_path,
      $.call_expression,
      $.field_expression,
      $.index_expression,
      $.struct_literal,
      $.array_literal,
      $.parenthesized_expression,
      $.match_expression,
      $.block,
      $.scope_expression,
      $.unsafe_expression,
      $.broadcast_expression,
    ),

    call_expression: $ => prec(16, seq(field('function', $._expression), field('arguments', $.arguments))),
    arguments: $ => seq('(', commaSep($._expression), optional(','), ')'),
    field_expression: $ => prec(17, seq(field('value', $._expression), '.', field('field', $.identifier))),
    index_expression: $ => prec(17, seq(
      field('value', $._expression), '[', commaSep1($._expression), optional(','), ']',
    )),
    broadcast_expression: $ => prec(17, seq(
      field('function', $._expression), '.', field('arguments', $.arguments),
    )),

    struct_literal: $ => seq(
      field('type', $.type_path), '{',
      commaSep($.struct_field), optional(','), '}',
    ),
    struct_field: $ => seq(field('name', $.identifier), '=', field('value', $._expression)),

    array_literal: $ => seq('[', commaSep($._expression), optional(','), ']'),

    some_expression: $ => prec(18, seq('some', $.arguments)),

    match_expression: $ => seq(
      'match', field('value', $._expression), '{',
      repeat($.match_arm), '}',
    ),
    match_arm: $ => seq($.pattern, '=>', field('value', $._expression), optional(',')),
    pattern: $ => choice(
      $.dot_variant,
      $.dot_variant,
      seq('.', $.member_name, $.field_pattern_list),
      seq('.', $.member_name, $.tuple_pattern),
      $.identifier,
      $._wildcard,
    ),
    field_pattern_list: $ => seq('{', commaSep(choice($.field_pattern, $.rest_pattern)), optional(','), '}'),
    rest_pattern: $ => '..',
    field_pattern: $ => seq(field('name', $.identifier), optional(seq(':', $.pattern)), optional(',')),
    tuple_pattern: $ => seq('(', commaSep($.pattern), ')'),

    scope_expression: $ => seq(
      'scope', $.arguments, field('body', $.block), optional(choice('!', '?')),
    ),
    unsafe_expression: $ => seq('unsafe', $.block),

    parenthesized_expression: $ => seq('(', $._expression, ')'),

    const_type: $ => seq(choice($.primitive_type, $.type_path, $.array_type), optional(choice('!', '?'))),

    type: $ => seq($._type_atom, optional(choice('!', '?'))),
    _type_atom: $ => choice(
      $.primitive_type,
      $.type_path,
      $.generic_type,
      $.array_type,
      $.slice_type,
      $.unit_literal,
    ),
    generic_type: $ => seq($.type_path, '(', commaSep(choice($.type, $.integer_literal)), optional(','), ')'),
    array_type: $ => seq('[', choice($.integer_literal, $.type_identifier), optional(seq(',', choice($.integer_literal, $.type_identifier))), ']', $.type),
    slice_type: $ => seq('[', ']', $.type),

    primitive_type: $ => choice(
      'bool', 'i8', 'i16', 'i32', 'i64', 'isize',
      'u8', 'u16', 'u32', 'u64', 'usize',
      'f32', 'f64', 'str', 'cstr', 'fault',
      'Io', 'Init', 'Allocator',
    ),

    type_path: $ => seq(
      field('head', $.type_identifier),
      repeat(seq('::', field('tail', $.member_name))),
    ),
    path: $ => seq($.identifier, repeat(seq('::', $.member_name))),

    _compile_time_name: $ => choice($.alias_name, $.identifier),
    alias_name: $ => token(/\$[A-Za-z_][A-Za-z0-9_]*/),
    dot_variant: $ => seq('.', $.member_name),
    _wildcard: $ => '_',

    function_name: $ => choice($.identifier, $.operator_symbol),
    operator_symbol: $ => choice(
      '+', '-', '*', '/', '%', '==', '!=', '<', '<=', '>', '>=',
    ),

    int_literal: $ => token(/[0-9][0-9_]*/),
    integer_literal: $ => $.int_literal,
    float_literal: $ => token(/[0-9][0-9_]*\.[0-9][0-9_]*/),
    string_literal: $ => $.string,
    string: $ => token(seq('"', repeat(choice(/[^"\\\n]/, /\\./)), '"')),
    bool_literal: $ => choice('true', 'false'),
    unit_literal: $ => seq('(', ')'),
    none_literal: $ => 'none',

    identifier: $ => /[a-z_][A-Za-z0-9_]*/,
    member_name: $ => choice($.identifier, $.type_identifier),
    type_identifier: $ => /[A-Z][A-Za-z0-9_]*/,

    macro_declaration: $ => seq(
      '@', field('name', $.identifier), '::', optional($.macro_parameters), $.macro_body,
    ),
    macro_parameters: $ => seq(
      '(', repeat(choice($.macro_parameter, ',', ';', $.decorator, $._macro_token)), ')',
    ),
    macro_parameter: $ => choice(
      seq($._compile_time_name, ':', choice('type', $.type)),
      $.hash_parameter,
    ),
    hash_parameter: $ => token(/#[A-Za-z_][A-Za-z0-9_]*/),
    macro_body: $ => seq('{', repeat(choice($.macro_body, $._macro_token)), '}'),
    _macro_token: $ => token(prec(-1, /[^{}]+/)),
  }
});

function commaSep(rule) {
  return optional(seq(rule, repeat(seq(',', rule))));
}

function commaSep1(rule) {
  return seq(rule, repeat(seq(',', rule)));
}
