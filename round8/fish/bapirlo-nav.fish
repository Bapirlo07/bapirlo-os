# Bapirlo OS — jump around faster (installed by 800-round8 … 820-round8.sh)
#   z proj        cd to the best match among folders you've visited ("frecency"), e.g. z dl → ~/Downloads
#   zi            pick one of them from a fuzzy list
#   Ctrl+R        fuzzy search through your command history (fzf)
#   Ctrl+T        insert a file path · Alt+C  cd into a sub-folder
# Off: delete ~/.config/fish/conf.d/bapirlo-nav.fish
status is-interactive; or exit

# Kuro palette: ink / paper text, crimson highlight, ember match, sakura info
set -gx FZF_DEFAULT_OPTS "--height=45% --layout=reverse --border=rounded --info=inline-right \
--prompt='❯ ' --pointer='▌' --marker='✚' \
--color=bg:-1,bg+:#231A1F,fg:#CAB5BF,fg+:#F2E9EC,hl:#FF4655,hl+:#FF4655 \
--color=border:#523B44,prompt:#E11D2E,pointer:#E11D2E,marker:#F08AA4,info:#8E7680,spinner:#F08AA4,header:#8E7680"
set -gx _ZO_FZF_OPTS $FZF_DEFAULT_OPTS

if type -q fzf
    fzf --fish | source
end
if type -q zoxide
    zoxide init fish | source
end
