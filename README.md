# lvim-fuzzy-zsh

The completion menu of zsh, in **lfz** ([lvim-fuzzy-cli](../lvim-fuzzy-cli)).

zsh's own completion system finds what can be typed — paths, commands, options, sub-commands, hosts, git branches, anything a completion function
offers, each with its description. This plugin shows all of it in lfz instead of zsh's menu: `Tab` completes as usual until the word is ambiguous,
then lfz opens with every candidate and what it is for, and the one you choose goes into the line.

```
❯ git <Tab>
  type to search…
  add       -- add file contents to the index
  bisect    -- find by binary search the change that introduced a bug
  branch    -- list, create, or delete branches
  ...
```

The look is lfz's `--minimal`: the prompt and the list, no title, counter, preview or footer.

## Install

Needs `lfz` (`lvim-fuzzy-cli`, `scripts/install.sh`) and zsh with `compinit`. In `~/.zshrc`, **after** `compinit` and before the plugins that wrap
widgets (zsh-autosuggestions, zsh-syntax-highlighting):

```zsh
source /path/to/lvim-fuzzy-zsh/lvim-fuzzy-zsh.plugin.zsh
# or with zinit:  zinit light lvim-tech/lvim-fuzzy-zsh
```

It replaces `fzf-tab`: do not load both.

## Use

| key | |
|---|---|
| `Tab` | complete; when there is a choice and nothing more is common, lfz opens |
| type | filter (lfz's own matching) |
| `Enter` | put the chosen word in the line, the way zsh would have (quoted, with the `/` of a directory, with a space after a command) |
| `Ctrl-P` | the preview of the row under the cursor, on and off: a directory shows what is in it, a text file its beginning, any other file what it is, any other candidate its whole text. The finder grows to make room for it |
| `Esc` | nothing chosen: the line stays as it was |

## Settings

With `zstyle`, before or after loading:

```zsh
zstyle ':lvim-fuzzy-zsh:*' command lfz                    # the finder (default: lfz, else lvim-fuzzy-cli)
zstyle ':lvim-fuzzy-zsh:*' flags --minimal --height=~60%  # its options (default: --minimal --height=~40%; the preview grows it to this)
zstyle ':lvim-fuzzy-zsh:*' disabled-on files              # contexts where zsh's own menu stays: any, files
zstyle ':lvim-fuzzy-zsh:*' bind '^I'                      # the key (default: Tab)
```

## How it works

- `compadd` — what every completion function calls to offer words — is wrapped: it remembers each word with its description and the context it is
  valid in (the prefix and suffix, `-P` / `-S` / `-f` and the like), and hands the words to zsh as well, so the completers know something matched.
- `_main_complete`, which runs the completion, is wrapped: when it has run, the finder opens with what was remembered. When all the candidates
  start with the same text, zsh's own insertion of it happens first (the next `Tab` opens the finder), as it does without the plugin.
- The chosen word is added in a second completion pass under the context it was offered in, so zsh inserts it exactly as it would from its menu.

## Not (yet) in it

Several choices at once, the group titles of zsh's menu.

## License

BSD-3-Clause
