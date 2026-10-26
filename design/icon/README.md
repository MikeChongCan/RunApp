# RunApp Icon Design

## Concept & Visual Metaphor

RunApp is a native macOS developer tool that builds and runs Xcode projects on simulators and USB/Wi-Fi devices without opening Xcode: **"press Play, it runs."**

The icon design bridges the command-line developer workflow (`runapp .`) with instant execution on target hardware:
1. **The Play Triangle (Action)**: The universal "Run" symbol in developer tools, sculpted with smooth macOS rounded vertices and an optical forward balance. Its silhouette evokes both a media play button and a terminal command prompt (`>`).
2. **The Device Plate (Target)**: A floating, frosted Liquid Glass plate representing the target device screen or simulator window, complete with subtle sensor pill and home indicator cues.
3. **The Graphite Canvas (Environment)**: A deep, authoritative developer neutral squircle backdrop with a subtle ambient blue radial glow, providing extreme contrast so the icon reads clearly at dock, spotlight, and menu-bar sizes down to 16×16 px.

## Layers & Liquid Glass Hierarchy

- **Base Squircle (macOS Container)**:
  - Light mode: Deep graphite neutral (`#262932` → `#0F1015`, `extended-srgb:0.145,0.157,0.188`)
  - Dark mode: Obsidian graphite (`#101114`, `extended-srgb:0.063,0.067,0.078`)
  - Ambient glow: `#0A66D6` at 22% opacity fading to 0%
- **Midground Layer (`plate.svg`)**:
  - Device/screen plate with 88px radius corners
  - Translucent frosted glass fill (`rgba(255, 255, 255, 0.16)` → `rgba(255, 255, 255, 0.04)`)
  - Beveled specular rim stroke (`rgba(255, 255, 255, 0.50)` → `rgba(255, 255, 255, 0.08)`)
  - Subtle hardware cues: top sensor pill (`462, 222, 100×8`) and bottom home indicator (`437, 798, 150×6`)
- **Foreground Layer (`play.svg`)**:
  - Sculpted play triangle (`408, 376` base to `682, 512` tip)
  - System Blue accent gradient: `#2EA5FF` (top light) → `#0A7AFF` → `#0058C6` (base)
  - Specular rim highlight: `rgba(255, 255, 255, 0.75)` fading to `rgba(0, 67, 153, 0.45)`
  - Elevated depth with multi-stop drop shadow

## Color Palette

| Role | Hex | sRGB Component Floats | Description |
| --- | --- | --- | --- |
| **Accent Primary** | `#0A66D6` | `0.039, 0.400, 0.839, 1.0` | macOS System Blue accent |
| **Accent Bright / Top** | `#2EA5FF` | `0.180, 0.647, 1.000, 1.0` | Top-lit specular blue highlight |
| **Accent Dark / Base** | `#0058C6` | `0.000, 0.345, 0.776, 1.0` | Deep blue shadow tone |
| **Dark Appearance Accent**| `#2986FF` | `0.161, 0.525, 1.000, 1.0` | High-vibrancy blue for dark mode |
| **Graphite Base (Top)** | `#262932` | `0.149, 0.161, 0.196, 1.0` | macOS developer neutral slate |
| **Graphite Base (Deep)**| `#0F1015` | `0.059, 0.063, 0.082, 1.0` | Obsidian squircle bottom |
| **Glass Plate Highlight**| `#FFFFFF` | `1.000, 1.000, 1.000, 0.5` | Translucent rim and specular bevel |

## Bundle Structure

- `design/icon/RunApp.svg`: 1024×1024 master standalone icon with full shadows and squircle container
- `design/icon/layers/plate.svg`: 1024×1024 device plate layer (transparent background)
- `design/icon/layers/play.svg`: 1024×1024 play glyph layer (transparent background)
- `RunApp/AppIcon.icon/`: Icon Composer bundle
  - `icon.json`: Manifest declaring `supported-platforms: {"squares": ["macOS"]}`, `fill-specializations`, shadows, translucency, and glass features
  - `Assets/plate.svg`: Device plate layer asset
  - `Assets/play.svg`: Play glyph layer asset
