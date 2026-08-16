#!/bin/bash

kitty --class "HyprMon" hyprmon
wait

kitty --class "Anarchy-Installer" sudo /usr/local/bin/anarchy-installer
