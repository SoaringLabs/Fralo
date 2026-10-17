# Installer background

background.png is the selected ImageGen artwork for the Fralo DMG. The full
generation prompt is in prompt.txt. It describes local batch screenshot framing
and transparent PNG export; the App and Applications icons are real Finder items.

scripts/generate-dmg-background.swift fits this artwork to a 660 × 400 logical
canvas and writes a 1320 × 800 TIFF. The packaging script aligns the actual icons
with the image's arrow and leaves room for Finder's title and status bars.

This directory is a build input for the installer, not an App runtime resource.
