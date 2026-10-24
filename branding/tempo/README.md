# Tempo T assets

The approved flowing T is maintained in mark.svg. The app icon uses an opaque navy background; the in-app and launch mark remain transparent. All versions use the same paths and gradients, with no neon/glow.

To regenerate: install sharp in your Node environment, or set TEMPO_SHARP_PATH to its package directory, then run node branding/tempo/build.cjs. The script updates all Xcode icon sizes, the transparent launch image and web SVG. Keep the AppIcon Contents.json mapping intact.
