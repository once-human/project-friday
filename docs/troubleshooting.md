# Troubleshooting

| Symptom | Try |
|---|---|
| Nothing happens on Super+Space | `qs -c friday` in a terminal shows QML errors. `hyprctl binds \| grep -i friday` checks the key. |
| "Sign in to Claude" keeps showing | Run `claude` once in a terminal and use `/login`. |
| No blur | `hyprctl layers \| grep friday` should show `quickshell:friday`. Check `hyprctl configerrors`. |
| Claude rings missing from the bar | `~/.local/share/friday/bin/friday-usage --debug`. `friday-integrate --status`. |
| ii updated and something looks off | `friday-integrate --revert`, then `friday-integrate` to re-apply. |
| Approval cards never appear | Friday must be running (`friday-start --restart`); otherwise risky actions are denied by design. |
| Warning about Qt version mismatch | Rebuild Quickshell (`yay -S quickshell`); this isn't caused by Friday. |
