# App Icon Guide

## Design concept
Blue background (#0079FF) with a white upward line chart — matches the app's `ledgerAccent` color and conveys wealth tracking at a glance.

## Sizes needed in AppIcon.appiconset
| File            | Size (pt) | Scale | Pixel size |
|-----------------|-----------|-------|------------|
| Icon-20@2x.png  | 20        | @2x   | 40×40      |
| Icon-20@3x.png  | 20        | @3x   | 60×60      |
| Icon-29@2x.png  | 29        | @2x   | 58×58      |
| Icon-29@3x.png  | 29        | @3x   | 87×87      |
| Icon-40@2x.png  | 40        | @2x   | 80×80      |
| Icon-40@3x.png  | 40        | @3x   | 120×120    |
| Icon-60@2x.png  | 60        | @2x   | 120×120    |
| Icon-60@3x.png  | 60        | @3x   | 180×180    |
| Icon-1024.png   | 1024      | @1x   | 1024×1024  |

## Quick generation (macOS)
Use `iconutil` or the free [AppIconGenerator](https://appicon.co) site:
1. Create a 1024×1024 PNG (see design below)
2. Upload to appicon.co → download the xcassets folder
3. Replace `Assets.xcassets/AppIcon.appiconset` in the Xcode project

## Design spec (for Figma / Sketch)
- Background: solid #0079FF (ledgerAccent)
- Icon: white `chart.line.uptrend.xyaxis` SF Symbol, 512pt, centred
- Corner radius: applied automatically by iOS (don't round the export)
