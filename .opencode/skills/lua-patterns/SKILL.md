# Lua Patterns ≠ Regex

Lua patterns are a different, simpler language. **Never import regex habits.**
Check [Lua 5.1 Patterns](https://www.lua.org/manual/5.1/manual.html#5.4.1)
before writing any `string.match`/`gmatch`/`gsub`.

## What Lua Patterns DO NOT have (common regex features)

| Feature | Regex | Lua | What happens |
|---------|-------|-----|-------------|
| Non-capturing groups | `(?:...)` | ❌ | `(` is always a capture; `?:` becomes literal chars inside the group |
| Alternation | `A\|B` | ❌ | `\|` is literal pipe; no `or` in patterns |
| Lookahead/lookbehind | `(?=...)` `(?<=...)` | ❌ | Syntax error or literal match |
| `\d` `\w` `\s` | shorthand | ❌ | `\d` matches literal `d`; use `%d` `%w` `%s` |
| `\D` `\W` `\S` | inverted | ❌ | Use `%D` `%W` `%S` |
| Greedy/lazy quantifiers | `*` greedy `*?` lazy | ⚠️ | All quantifiers are greedy (`*` `+` `?`); `-` is the lazy equivalent of `*` |
| `?` alone | optional | ⚠️ | `?` is a **quantifier** — must follow a character or class; `/?` matches `/` or empty |
| Anchor mid-pattern | `$` `^` anywhere | ⚠️ | `$` only anchors at **end of pattern**; `^` only at **start**; inside a group they're literal |
| `\` escapes | `\.` `\(` | ❌ | Use `%.` `%(` — `%` is the Lua escape for magic chars |

## Lua Pattern Quick Reference

```
.       any character
%a      letter
%d      digit
%w      alphanumeric
%s      whitespace (space, \t, \n, \r, \v, \f)
%l      lowercase letter
%u      uppercase letter
%p      punctuation
%x      hex digit
%c      control character
%1-%9   back-reference to capture group
%b()    balanced pair (e.g. %b() matches ( ... ))

[...]   character set (^ at start = negation)
+       1 or more (greedy)
*       0 or more (greedy)
-       0 or more (lazy — Lua's *?)
?       0 or 1 (greedy)
^       anchor at string start
$       anchor at string end
```

## Common Pitfall: Splitting by blank lines

❌ Wrong (regex syntax — silently matches nothing):
```lua
for block in text:gmatch("(.-)(?:\r?\n\r?\n|$)") do
```

✅ Correct (Lua pattern — append sentinel to capture last block):
```lua
for block in (text .. "\n\n"):gmatch("(.-)\r?\n\r?\n") do
```

## Common Pitfall: `(.-)` with `$` anchor

Captures are greedy by default. Use `-` (lazy) inside a capture group when
matching up to a known delimiter. If you need to match up to end of string,
append a sentinel instead of relying on `$` inside a group.