# KeyCoach README demo — render with: vhs assets/demo.tape
#
# The data directory is pre-seeded with three prior sessions of evidence
# (seeded through the real engine+store pipeline), so the dashboard shows
# genuine recommendations. The :Telescope stub lets the recording capture
# a real command invocation on camera.
#
# After rendering, slow playback to ~0.75x without re-encoding:
#   python3 assets/scale-gif-delays.py assets/demo.gif assets/demo.gif

Output assets/demo.gif
Set Shell bash
Set FontFamily "Hack"
Set FontSize 14
Set Width 1420
Set Height 800
Set Theme "Catppuccin Mocha"
Set Padding 32
Set TypingSpeed 40ms
Set WindowBar "Colorful"
Set BorderRadius 8

Hide
Type "export XDG_DATA_HOME=/home/actual/kc-demo/data"
Enter
Type "clear"
Enter
Type "nvim -u /home/actual/kc-demo/init.lua"
Enter
Show
Sleep 1800ms

Type "G"
Sleep 500ms
Type "jjkk"
Sleep 900ms

Type ":Telescope find_files"
Enter
Sleep 1800ms

Type "G"
Sleep 600ms

Type ":KeyCoach"
Enter
Sleep 2600ms

Enter
Sleep 1200ms

Type "y"
Sleep 1800ms

Enter
Sleep 600ms

Type "q"
Sleep 800ms

Type ":e /home/actual/kc-demo/mappings.lua"
Enter
Sleep 2400ms

Type ":qa!"
Enter
Sleep 400ms
