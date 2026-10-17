# App icon

Fralo.icon contains the layered source for the current App icon, including the SVG
layers in Assets/. It is included in the repository and licensed under MIT.

scripts/package.py compiles it with Xcode 27's actool into Assets.car and the
Fralo.icns fallback, and merges the generated icon metadata into Info.plist.
No local design-history files are required to rebuild the App.
