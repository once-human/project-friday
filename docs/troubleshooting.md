# Troubleshooting

| Symptom | Try |
|---|---|
| Anything at all | `project-friday status` first, then `project-friday logs`. |
| Friday is stuck on screen | `project-friday restart`. It also stops a request on its own after 3 minutes of silence. |
| `project-friday: command not found` | `~/.local/bin` isn't on your PATH: open a new terminal after installing, or run `~/.local/bin/project-friday`. |
| Nothing happens on Super+Space | `qs -c friday` in a terminal shows QML errors. `hyprctl binds \| grep -i friday` checks the key. |
| "Sign in to Claude" keeps showing | Run `claude` once in a terminal and use `/login`. |
| No blur | `hyprctl layers \| grep friday` should show `quickshell:friday`. Check `hyprctl configerrors`. |
| Claude rings missing from the bar | `project-friday usage`. `friday-integrate --status`. |
| ii updated and something looks off | `friday-integrate --revert`, then `friday-integrate` to re-apply. |
| Approval cards never appear | Friday must be running (`project-friday restart`); otherwise risky actions are denied by design. |
| Warning about Qt version mismatch | Rebuild Quickshell (`yay -S quickshell`); this isn't caused by Friday. |
