# Generated demo screenshots

These fictional "Field Notes" screens contain no real user or application data.
They demonstrate Fralo's PNG workflow and are distributed under the MIT license.

Regenerate the three portrait inputs (1320 × 2868):

    swift scripts/generate-demo.swift examples

After building the CLI:

    ./dist/fralo render examples --output artifacts/demo-output \
      --model iphone-18-pro-max --orientation portrait --padding 0 --json

Choose this folder in the App to reproduce the README screenshots.
The renderer adds the device frame, rounded screen corners, and Dynamic Island.
The examples are illustration inputs, not a shipping "Field Notes" product.
