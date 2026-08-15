#!/bin/bash
# Anarchy Linux Live ISO Launcher
# Runs hyprmon first to configure monitors, then launches the installer

# Launch hyprmon in its own kitty window
kitty --class=hyprmon -e hyprmon

# Once hyprmon exits, launch installer (hold keeps window open on exit)
kitty --class=anarchy-installer -e bash -c "sudo /usr/local/bin/anarchy-installer.sh; read"
