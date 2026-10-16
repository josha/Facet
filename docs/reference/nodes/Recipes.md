## Recipes

<!-- aliases: Recipes | recipes -->

`Facet.recipes.arithmetic.parse(text)` returns a finite number or `nil` for
any value. Give it to a number field as `parse`. It accepts `+`, `-`, `*`, `/`,
parentheses, the typographic signs `×`, `÷` and `−`, and blanks. It refuses a
division by zero, an exponent, a hex number, more than 256 characters and more
than 32 levels of nesting. It never compiles the text.
