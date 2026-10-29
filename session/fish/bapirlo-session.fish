# Kuro Session — terminal folders survive log out / restart.
# Each interactive fish remembers its folder; after a login restore, the reopened terminals
# (they start in ~) each take back one saved folder. Normal new terminals are untouched.
# Off: delete ~/.config/fish/conf.d/bapirlo-session.fish
status is-interactive; or exit

set -l __bs_state (set -q XDG_STATE_HOME; and echo $XDG_STATE_HOME; or echo $HOME/.local/state)/bapirlo-session
set -g __bapirlo_shell_file $__bs_state/shells/$fish_pid
mkdir -p $__bs_state/shells

if test "$PWD" = "$HOME"; and test -d $__bs_state/pending
    for f in $__bs_state/pending/*
        string match -qr '^\d+$' -- (path basename $f); or continue
        # only folders handed out by a restore in the last 3 minutes
        if test (math (date +%s) - (path mtime $f)) -gt 180
            rm -f $f
            continue
        end
        if mv $f $f.$fish_pid 2>/dev/null       # atomic: one folder per terminal
            set -l dir (cat $f.$fish_pid)
            rm -f $f.$fish_pid
            test -d "$dir"; and cd "$dir"
            break
        end
    end
end

function __bapirlo_save_pwd --on-variable PWD
    echo $PWD > $__bapirlo_shell_file
end
__bapirlo_save_pwd

function __bapirlo_forget_pwd --on-event fish_exit
    rm -f $__bapirlo_shell_file
end
