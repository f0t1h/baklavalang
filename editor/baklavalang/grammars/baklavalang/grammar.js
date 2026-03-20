module.exports = grammar({
  name: "baklavalang",

  extras: ($) => [/\s/],

  word: ($) => $.identifier,

  conflicts: ($) => [],

  rules: {
    source_file: ($) =>
      seq(
        repeat(choice($.grid_definition, $.comment)),
        optional($.main_section)
      ),

    grid_definition: ($) =>
      seq(
        field("name", $.identifier),
        "[",
        repeat($._statement),
        "]"
      ),

    _statement: ($) =>
      choice(
        $.receive_clause,
        $.let_binding,
        $.halt,
        $.if_expression,
        $.comment,
        $._expression
      ),

    receive_clause: ($) =>
      prec(10, seq(
        "#",
        $.flow_operator,
        $._pattern,
        "=>",
        choice(
          $.block,
          $._statement
        )
      )),

    let_binding: ($) =>
      seq("let", $.identifier, "=", $._expression),

    halt: ($) => prec(1, "halt"),

    if_expression: ($) =>
      seq(
        "if",
        $._expression,
        $.block,
        optional(seq("else", $.block))
      ),

    block: ($) => seq("{", repeat($._statement), "}"),

    // Patterns
    _pattern: ($) =>
      choice(
        $.wildcard_pattern,
        $.tuple_pattern,
        $.list_pattern,
        $.pattern_identifier,
        $.number,
        $.string
      ),

    wildcard_pattern: ($) => "_",

    pattern_identifier: ($) => /[a-z][a-zA-Z0-9_]*/,

    tuple_pattern: ($) =>
      seq("{", $._pattern, repeat(seq(",", $._pattern)), "}"),

    list_pattern: ($) =>
      choice(
        seq("[", "]"),
        seq("[", $._pattern, "|", $._pattern, "]"),
        seq("[", $._pattern, repeat(seq(",", $._pattern)), "]")
      ),

    // Expressions
    _expression: ($) =>
      choice(
        $.emit_expression,
        $.binary_expression,
        $._primary
      ),

    emit_expression: ($) =>
      choice(
        prec.right(0, seq($._expression, $.flow_operator, "$")),
        prec.right(0, seq("$", $.flow_operator, $._expression))
      ),

    binary_expression: ($) =>
      choice(
        prec.left(2, seq($._expression, choice("==", "!=", "<=", ">=", "<", ">"), $._expression)),
        prec.left(3, seq($._expression, choice("+", "-"), $._expression)),
        prec.left(4, seq($._expression, choice("*", "/"), $._expression))
      ),

    _primary: ($) =>
      choice(
        $.number,
        $.string,
        $.boolean,
        $.module_call,
        $.erlang_module_call,
        $.function_call,
        $.identifier,
        $.tuple,
        $.list,
        $.hash,
        $.paren_expression
      ),

    paren_expression: ($) => seq("(", $._expression, ")"),

    module_call: ($) =>
      prec(5, seq(
        field("module", $.module_name),
        ".",
        field("function", $.identifier),
        "(",
        optional(seq($._expression, repeat(seq(",", $._expression)))),
        ")"
      )),

    erlang_module_call: ($) =>
      prec(5, seq(
        field("module", $.erlang_module),
        ".",
        field("function", $.identifier),
        "(",
        optional(seq($._expression, repeat(seq(",", $._expression)))),
        ")"
      )),

    function_call: ($) =>
      prec(5, seq(
        field("function", $.identifier),
        "(",
        optional(seq($._expression, repeat(seq(",", $._expression)))),
        ")"
      )),

    tuple: ($) =>
      prec(1, seq("{", $._expression, repeat(seq(",", $._expression)), "}")),

    list: ($) =>
      choice(
        seq("[", "]"),
        seq("[", $._expression, "|", $._expression, "]"),
        seq("[", $._expression, repeat(seq(",", $._expression)), "]")
      ),

    // Main section
    main_section: ($) =>
      prec(100, seq(
        "main",
        ":",
        repeat1($._main_cell)
      )),

    _main_cell: ($) =>
      prec(100, choice(
        $.relay_symbol,
        $.empty_cell,
        $.grid_ref
      )),

    grid_ref: ($) => prec(100, $.identifier),

    relay_symbol: ($) =>
      choice(
        "-->>", "-->^", "-->v",
        "<<--", "^<--", "v<--",
        "<--v", "v-->", "vvvv",
        "<--^", "^-->", "^^^^"
      ),

    empty_cell: ($) => "____",

    // Terminals
    hash: ($) => "#",
    flow_operator: ($) => choice("|>", "<|", "|^", "|v"),
    module_name: ($) => /[A-Z][a-zA-Z0-9_]*/,
    erlang_module: ($) => seq(":", /[a-z][a-zA-Z0-9_]*/),
    identifier: ($) => /[a-z_][a-zA-Z0-9_]*/,
    number: ($) => /\d+/,
    string: ($) => /"[^"\\]*(?:\\.[^"\\]*)*"/,
    boolean: ($) => choice("true", "false"),
    comment: ($) => token(seq("//", /.*/)),
  },
});
