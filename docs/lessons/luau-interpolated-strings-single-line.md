# Luau interpolated strings are single-line only

Backtick-interpolated strings (`` `x = {value}` ``) cannot span lines and
cannot contain `{{`/`}}` (a doubled brace is a syntax error, not an escape —
use `\{`). Multi-line templates (scaffold stamps, generated file bodies) must
be `[==[ … ]==]` long strings with placeholder substitution
(`string.gsub(template, "%%NAME%%", name)`), NOT interpolation. Hit twice in
one session writing tools/lune/scaffold.luau (template bodies and again in
the plan's edit inserts).
