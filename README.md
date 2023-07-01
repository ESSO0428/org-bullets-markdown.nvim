# Org-bullets-markdown.nvim

This plugin is a clone of [org-bullets](https://github.com/sabof/org-bullets).
It replaces the asterisks in org syntax with unicode characters.

This plugin is an extension intended for use with `markdown`
This plugin works by using neovim `extmarks`, rather than `conceal` for a few reasons.

- conceal can only have one global highlight see `:help hl-Conceal`.
- conceal doesn't work when a block is folded.

_see below for a simpler conceal-based solution_

![folded](https://user-images.githubusercontent.com/22454918/125088455-525df300-e0c5-11eb-9b36-47c238b46971.png)

## Pre-requisites

- **This plugin requires the use of treesitter with `tree-sitter-markdown` installed**
- neovim 0.7+

## Installation

#### With packer.nvim

```lua
use 'ESSO0428/org-bullets-markdown.nvim'
```

## Usage

To use the defaults use:

```lua
use {'ESSO0428/org-bullets-markdown.nvim', config = function()
  require('org-bullets-markdown').setup()
end}
```

The full options available are:

**NOTE**: Do **NOT** copy and paste this block as it is not valid, it is just intended to show the available configuration options

```lua
use {"ESSO0428/org-bullets-markdown.nvim", config = function()
  require("org-bullets-markdown").setup {
    show_current_line = false, -- If false then when the cursor is on a line underlying characters are visible
    symbols = {
      -- headlines can be a list
      mkd_bullets = { "◉", "○", "✸", "•", "◦" },
      checkboxes = { "˟", "✓" },
    }
  }
end}
```

