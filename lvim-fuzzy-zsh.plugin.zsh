# lvim-fuzzy-zsh: the completion menu of zsh through lfz (lvim-fuzzy-cli).
#
# zsh's own completion (compsys) finds what can be typed — paths, commands, options, sub-commands, hosts, git branches, anything a completion
# function offers, each with its description — and this plugin shows all of it in lfz instead of zsh's menu. Tab completes as usual until the
# word is ambiguous; then lfz opens with every candidate and its description, and the choice is put in the line.
#
# How: `compadd` (what every completion function calls to offer words) is wrapped to remember what it is given, `_main_complete` (what runs
# the completion) is wrapped to open lfz after it has run, and the chosen word is added the way the completion function would have added it.
#
#   zstyle ':lvim-fuzzy-zsh:*' command lfz                  # the finder (default: lfz, else lvim-fuzzy-cli)
#   zstyle ':lvim-fuzzy-zsh:*' flags --minimal --height=~60%   # its options (default: --minimal --height=~40%)
#   zstyle ':lvim-fuzzy-zsh:*' disabled-on files            # contexts where plain zsh completion stays (a list of: any, files)
#   zstyle ':lvim-fuzzy-zsh:*' bind '^I'                    # the key (default: Tab)

[[ -o interactive ]] || return 0
zmodload zsh/zutil 2>/dev/null
zmodload zsh/datetime 2>/dev/null

# the finder
typeset -g _lvfz_cmd
() {
  local c
  zstyle -s ':lvim-fuzzy-zsh:' command c || c=
  [[ -n $c ]] || { (( $+commands[lfz] )) && c=lfz || c=lvim-fuzzy-cli }
  (( $+commands[${c%% *}] )) || {
    print -u2 "lvim-fuzzy-zsh: '${c%% *}' (lfz, from lvim-fuzzy-cli) is not installed: the plugin is not loaded"
    return 1
  }
  _lvfz_cmd=$c
} || return 0

# what the wrapped compadd collects while Tab runs the completion
typeset -g  _lvfz_on=0                 # 1 while the Tab widget runs completion
typeset -ga _lvfz_disp _lvfz_ctx       # per candidate: the line shown, and what is needed to add it again
typeset -ga _lvfz_path                 # per candidate: the file it is, when it is one (for the preview)
typeset -g  _LVFZ_DIR=${${(%):-%x}:A:h}   # where this file is (the preview script is next to it)
typeset -gA _lvfz_seen                 # candidates already collected (a completer may offer one twice)
typeset -ga _lvfz_choice               # what was chosen: the contexts to add
typeset -g  _lvfz_cut=                 # what stood after the cursor in the word completed (SUFFIX): the chosen word replaces the whole word
typeset -gi _lvfz_picked=0             # 1 when the finder was left with Tab on a choice (this round): go on inside it

# compadd takes every completion function's candidates: remember them (with the context they are valid in), and let zsh have them as well, so
# the completers know that something matched
_lvfz_compadd() {
  local -A apre hpre dscrs _oad
  local -a isfile _opts __ expl
  zparseopts -a _opts P:=apre p:=hpre d:=dscrs X+:=expl O:=_oad A:=_oad D:=_oad f=isfile \
             i: S: s: I: x: r: R: W: F: M+: E: q e Q n U C \
             J:=__ V:=__ a=__ l=__ k=__ o::=__ 1=__ 2=__

  # not while Tab is completing, and not when the caller only asks zsh a question (-O, -A, -D): zsh's own
  if (( ! _lvfz_on || $#_oad != 0 )); then
    builtin compadd "$@"
    return
  fi
  # a context the user keeps plain
  local dis
  zstyle -a ':lvim-fuzzy-zsh:' disabled-on dis
  if (( ${dis[(I)any]} )) || { (( ${dis[(I)files]} )) && [[ -n $isfile ]] }; then
    builtin compadd "$@"
    return
  fi

  # the words that match what is typed, and their descriptions (the same ones, in the same order)
  local -a hits dscr
  (( $#dscrs == 1 )) && dscr=( "${(@P)${(v)dscrs}}" )
  builtin compadd -A hits -D dscr "$@"
  local ret=$?
  (( $#hits )) || return $ret

  # LVFZ_DEBUG=/some/file: what each completion function offered, to find out why a candidate has no file or icon
  [[ -n $LVFZ_DEBUG ]] && print -r -- "${EPOCHREALTIME:-0} compadd isfile=[$isfile] IPREFIX=[$IPREFIX] PREFIX=[$PREFIX] hpre=[${(kv)hpre}] apre=[${(kv)apre}] opts=[${_opts}] first=[$hits[1]] n=$#hits" >> $LVFZ_DEBUG
  _opts+=("${(@kv)apre}" "${(@kv)hpre}" $isfile)
  local args=${(pj:\2:)_opts}
  # a file the candidate stands for: the directory typed before it (hidden prefix, with ~ and variables expanded) and the word, unquoted
  local dirpart=
  [[ -n $isfile ]] && dirpart=${(Qe)~${:-$IPREFIX${hpre[-p]}}}
  local i word shown key
  for i in {1..$#hits}; do
    word=$hits[i]
    shown=${dscr[i]:-$word}
    shown=${shown//[$'\n\t']/ }
    # a directory shows with its /, whatever the completion function showed
    [[ -n $isfile && -d $dirpart${(Q)word} && $shown != */ ]] && shown+=/
    key=$word$'\1'$IPREFIX$'\1'$PREFIX$'\1'$SUFFIX$'\1'$ISUFFIX$'\1'$args
    (( $+_lvfz_seen[$key] )) && continue
    _lvfz_seen[$key]=1
    _lvfz_disp+=$shown
    _lvfz_ctx+=$key
    # the file a candidate stands for: when the completion says it is one (-f), or, when it does not say, when the word is a file or directory that
    # is there (a completion function that adds its directories without -f)
    if [[ -n $isfile ]]; then
      _lvfz_path+=$dirpart${(Q)word}
    else
      # (the word may carry its own directory, `~/.zshrc`, and a space after it: the file is what it names with the ~ expanded)
      local w=${(Q)word}
      w=${w%%[[:space:]]#}
      w=${w/#\~\//$HOME/}
      [[ $w == '~' ]] && w=$HOME
      if [[ -e $w ]]; then _lvfz_path+=$w; else _lvfz_path+=; fi
    fi
  done

  # zsh's own, so that the completion counts as having matched
  builtin compadd "$@"
}

# _main_complete runs the completion functions. Wrapped: when Tab runs it, lfz opens after it, to choose among what was collected.
_lvfz_complete() {
  if (( ! _lvfz_on )); then
    _lvfz__main_complete "$@"
    return
  fi
  local ret=0
  # (user options on, as the completion functions expect; a wide terminal, so that nothing is cut for a list we do not show)
  () {
    setopt localoptions no_monitor no_notify
    COLUMNS=500 _lvfz__main_complete "$@"
  } "$@" || ret=$?

  emulate -L zsh -o extended_glob

  case $#_lvfz_ctx in
    0) return 1 ;;
    1) _lvfz_choice=($_lvfz_ctx[1]) ;;
    *)
      # zsh would first add what all the candidates start with: let it (the next Tab opens the finder), as it does without the plugin
      if [[ $compstate[insert] == *unambiguous ]] \
        && [[ -n $compstate[unambiguous] ]] \
        && [[ $compstate[unambiguous] != "$compstate[quote]$IPREFIX$PREFIX$compstate[quote]" ]] \
        && [[ $compstate[list] != *force* ]]; then
        compstate[list]=
        compstate[insert]=unambiguous
        return 0
      fi

      local -a lines flags paths
      local i
      for i in {1..$#_lvfz_ctx}; do
        # (the third field is the file the candidate stands for, if it is one: lfz's own previewers — a directory with icons, a file highlighted, an
        # image — show it)
        lines+=$i$'\t'$_lvfz_disp[i]$'\t'$_lvfz_path[i]
        paths+=$_lvfz_path[i]$'\t'$_lvfz_disp[i]
      done
      zstyle -a ':lvim-fuzzy-zsh:' flags flags || flags=(--minimal --height='~40%')
      # Ctrl-P: the preview of the row under the cursor: lfz's own for a file or a directory (the target above), and for any other candidate its
      # whole text (a command of ours, which reads its row from a file of the candidates).
      local pf=${TMPDIR:-/tmp}/lvim-fuzzy-zsh.$$.paths
      print -rl -- $paths >| $pf
      flags+=(--preview="$_LVFZ_DIR/lvfz-preview ${(q)pf} {1}")
      local out
      # the finder draws from the line the cursor is on: one line down first, so that the line being typed stays on the screen; and back up after
      # (the preview opens on the right, whatever side lfz remembers for its own runs; flags of your own come after and can say otherwise)
      # (the cursor is hidden meanwhile: it does not jump down and wait, the finder shows its own where the field is; and it stays hidden when
      # the finder ends, until it is back on the line: --exit-cursor=hidden)
      echoti civis >/dev/tty 2>/dev/null
      print -n '\n' >/dev/tty
      out=$(print -rl -- $lines | ${(z)_lvfz_cmd} --preview-window=right $flags --exit-cursor=hidden --delimiter=$'\t' --with-nth=2 --accept-nth=1 --target='{3}' --expect=tab --bind=shift-tab:ignore --no-multi)
      local fret=$?
      command rm -f -- $pf
      echoti cuu1 >/dev/tty 2>/dev/null
      echoti cnorm >/dev/tty 2>/dev/null
      # Esc: nothing is chosen, the line stays as it was
      if (( fret != 0 )) || [[ -z $out ]]; then
        compstate[list]=
        compstate[insert]=
        return 1
      fi
      # (--expect=tab: the first line is the key that ended it — `tab`, or empty for Enter — then the chosen rows)
      _lvfz_choice=()
      local -a res=("${(@f)out}")
      [[ $res[1] == tab ]] && _lvfz_picked=1
      local n
      for n in $res[2,-1]; do
        [[ $n == <-> ]] && _lvfz_choice+=$_lvfz_ctx[n]
      done
      ;;
  esac

  # what zsh would show or insert is not wanted: the chosen word is added next (_lvfz_apply)
  compstate[list]=
  compstate[insert]=
  return $ret
}

# The second completion pass: add the chosen word under the context it was offered in, so zsh inserts it (quoting, a prefix, a suffix such as
# the / of a directory) exactly as it would have inserted the word from its own menu.
_lvfz_apply() {
  local c
  for c in $_lvfz_choice; do
    local -a f=("${(@ps:\1:)c}")
    local -a args=("${(@ps:\2:)f[6]}")
    [[ -z $args[1] ]] && args=()
    IPREFIX=${f[2]-} PREFIX=${f[3]-} SUFFIX=${f[4]-} ISUFFIX=${f[5]-}
    _lvfz_cut=${f[4]-}
    builtin compadd "${args[@]:--Q}" -Q -- "$f[1]"
  done
  compstate[list]=
  if (( $#_lvfz_choice == 1 )); then
    compstate[insert]=1
    [[ $RBUFFER == ' '* ]] || compstate[insert]+=' '
  elif (( $#_lvfz_choice > 1 )); then
    compstate[insert]=all
  fi
}

# The Tab widget: complete (collecting what is offered; the finder opens when there is a choice), then add what was chosen.
_lvfz_tab() {
  setopt localoptions
  local -i ret=0 round=0 again=1
  while (( again )); do
    again=0
    (( round++ ))
    # (the rounds after the first complete inside a directory just chosen: when it has nothing to offer there is no beep)
    (( round > 1 )) && unsetopt beep
    _lvfz_disp=() _lvfz_ctx=() _lvfz_choice=() _lvfz_path=()
    _lvfz_seen=()
    _lvfz_picked=0
    _lvfz_on=1
    {
      # (the widget with compsys, not the dotted builtin: only that one runs _main_complete)
      zle expand-or-complete || ret=$?
      if (( $#_lvfz_choice )); then
        zle _lvfz_apply_widget || ret=$?
        # the cursor was inside the word (`vim ~/.zsh|rc`): what stood after it is part of the word that was replaced, so it goes (a completion that
        # keeps the suffix in its matches, as zsh's own does, has put it back by itself)
        if [[ -n $_lvfz_cut && ${RBUFFER[1,${#_lvfz_cut}]} == "$_lvfz_cut" ]]; then
          RBUFFER=${RBUFFER[$(( ${#_lvfz_cut} + 1 )),-1]}
        fi
      fi
    } always {
      _lvfz_on=0
    }
    # Tab in the finder on a directory (the line ends in /): the finder opens again on what is inside it, until there is nothing more to choose (a
    # directory with nothing in it, a file), Enter (which chooses and ends) or Esc
    if (( _lvfz_picked )) && [[ $LBUFFER == */ ]]; then
      again=1
      zle -R
    fi
  done
  # lfz gave the cursor back as the terminal's default; the shell's own shape (zsh-vi-mode's bar in insert mode) comes back
  (( $+functions[zvm_update_cursor] )) && zvm_update_cursor
  # (redisplay: the line is drawn again with the prompt as it is; `reset-prompt` would run a prompt that is a command, like starship's, again)
  zle .redisplay
  return $ret
}

# Turn it on: wrap _main_complete and compadd once, make the widgets, bind the key.
_lvfz_enable() {
  # the real _main_complete is loaded and kept under another name
  if (( ! $+functions[_lvfz__main_complete] )); then
    autoload +X -Uz _main_complete 2>/dev/null
    (( $+functions[_main_complete] )) || return 1
    functions[_lvfz__main_complete]=$functions[_main_complete]
    functions[_main_complete]='_lvfz_complete "$@"'
  fi
  functions[compadd]='_lvfz_compadd "$@"'
  zle -N _lvfz_tab
  zle -C _lvfz_apply_widget complete-word _lvfz_apply
  local key keymap
  zstyle -s ':lvim-fuzzy-zsh:' bind key || key='^I'
  for keymap in emacs viins main; do
    bindkey -M $keymap $key _lvfz_tab 2>/dev/null
  done
}

# zsh-vi-mode and other ZLE plugins set their keymaps at the first prompt: bind once more then, after them
_lvfz_late() {
  add-zsh-hook -d precmd _lvfz_late
  _lvfz_enable
}
autoload -Uz add-zsh-hook
_lvfz_enable && add-zsh-hook precmd _lvfz_late
