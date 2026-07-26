/// <reference types="tree-sitter-cli/dsl" />

module.exports = grammar({
  name: 'poste_json',

  extras: $ => [
    /\s/,
    $.comment,
  ],

  supertypes: $ => [
    $.value,
  ],

  rules: {
    document: $ => repeat($.value),

    value: $ => choice(
      $.object,
      $.array,
      $.string,
      $.number,
      $.boolean,
      $.null,
      $.variable,
    ),

    object: $ => seq(
      '{',
      optional(seq(
        $.member,
        repeat(seq(',', $.member)),
      )),
      optional(','),
      '}',
    ),

    member: $ => seq(
      $.key,
      ':',
      $.value,
    ),

    key: $ => $.string,

    array: $ => seq(
      '[',
      optional(seq(
        $.value,
        repeat(seq(',', $.value)),
      )),
      optional(','),
      ']',
    ),

    string: $ => seq(
      '"',
      repeat(choice(
        /[^\\"\n]/,
        /\\./,
      )),
      '"',
    ),

    number: $ => token(seq(
      optional('-'),
      choice(
        seq('0', optional(seq('.', /[0-9]+/))),
        seq(/[1-9]/, /[0-9]*/, optional(seq('.', /[0-9]+/))),
      ),
      optional(seq(/[eE]/, optional(/[+-]/), /[0-9]+/)),
    )),

    boolean: $ => choice('true', 'false'),

    null: $ => 'null',

    variable: $ => seq(
      '{{',
      optional(/\s+/),
      /[^}]+(?:}[^}]+)*/,
      optional(/\s+/),
      '}}',
    ),

    comment: $ => token(seq('#', /[^\n]*/)),
  },
})