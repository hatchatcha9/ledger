# Ledger — Mac Setup & App Store Submission

Everything in this doc is a one-time step on a Mac with Xcode 15+.

---

## 1. Create the Xcode project

There is no `.xcodeproj` file yet — create one now.

1. Open **Xcode** → **File → New → Project → iOS → App**
2. Fill in:
   - **Product Name**: `Ledger`
   - **Team**: your Apple Developer account (or "None" for now)
   - **Bundle Identifier**: `com.yourname.ledger` (swap your name in)
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Storage**: None (we have a custom CoreData stack)
   - Uncheck **Include Tests**
3. When asked where to save: choose **Desktop** (or anywhere convenient).
   Xcode creates `Desktop/Ledger/Ledger.xcodeproj`.

---

## 2. Copy the source files onto the Mac

Transfer the `ledger/` folder (from Windows) into the Xcode project folder so
the layout looks like this:

```
~/Desktop/Ledger/
    Ledger.xcodeproj
    ledger/               ← everything you wrote on Windows
        App/
        Core/
        CoreData/
        Features/
        Shared/
        LedgerWidget/
        Ledger.xcdatamodeld/
```

---

## 3. Delete Xcode's generated default files

Xcode auto-generated `ContentView.swift` and a `LedgerApp.swift` with its own
`@main`. Ours already has `@main`, so these must go or the project won't compile.

In the Xcode **Project Navigator**, right-click each file → **Delete → Move to Trash**:

- `ContentView.swift` (the template placeholder)
- `LedgerApp.swift` (the template entry-point — we have our own in `ledger/App/`)

Keep `Assets.xcassets` — we'll add the app icon to it later.

---

## 4. Add all source files to the Ledger target

In the Project Navigator, right-click the blue **Ledger** folder icon →
**Add Files to "Ledger"…**

In the file picker, navigate into `ledger/` and add these folders one at a time.
For each, set:
- **Added folders**: Create groups
- **Add to targets**: ✅ Ledger

Folders to add (from inside `ledger/`):

```
App/
Core/
CoreData/
Features/
Shared/
```

*Skip `LedgerWidget/` — it goes to the widget target you'll create in Step 7.*

---

## 5. Add the Core Data model

The model file is a folder on disk, not a plain `.swift` file.

1. In Finder, open `ledger/` and locate `Ledger.xcdatamodeld`
2. Drag it into the Xcode Project Navigator (drop it on the blue **Ledger** group)
3. In the dialog: **Added folders → Create groups**, **Add to targets → ✅ Ledger**

---

## 6. Info.plist — add Face ID usage string

Select the **Ledger** target → **Info** tab → click **+** → add:

| Key | Value |
|-----|-------|
| `NSFaceIDUsageDescription` | `Unlock Ledger to see your finances.` |

---

## 7. App Group capability (main target)

Select the **Ledger** target → **Signing & Capabilities** → **+ Capability** →
**App Groups**. Add:

```
group.ledger
```

---

## 8. Add the Widget Extension target

1. **File → New → Target → Widget Extension**
   - Product Name: `LedgerWidget`
   - Uncheck **"Include Configuration Intent"**
   - Click **Finish**, then **Activate** the new scheme if prompted

2. In the Project Navigator, right-click the new **LedgerWidget** group →
   **Add Files to "LedgerWidget"…**
   Add (one at a time, target: ✅ LedgerWidget):

   ```
   ledger/LedgerWidget/LedgerWidget.swift
   ledger/Core/Persistence/PersistenceController.swift
   ledger/Core/Services/HapticService.swift
   ledger/Shared/Theme/Theme.swift
   ledger/Shared/Models/AccountType.swift
   ledger/Shared/Models/AssetType.swift
   ledger/Shared/Models/TransactionCategory.swift
   ledger/Shared/Models/RecurringFrequency.swift
   ledger/CoreData/Account/Account+CoreDataClass.swift
   ledger/CoreData/Account/Account+CoreDataProperties.swift
   ledger/CoreData/Account/Account+Extensions.swift
   ledger/CoreData/Asset/Asset+CoreDataClass.swift
   ledger/CoreData/Asset/Asset+CoreDataProperties.swift
   ledger/CoreData/Asset/Asset+Extensions.swift
   ledger/CoreData/Budget/Budget+CoreDataClass.swift
   ledger/CoreData/Budget/Budget+CoreDataProperties.swift
   ledger/CoreData/Budget/Budget+Extensions.swift
   ledger/CoreData/RecurringTransaction/RecurringTransaction+CoreDataClass.swift
   ledger/CoreData/RecurringTransaction/RecurringTransaction+CoreDataProperties.swift
   ledger/CoreData/RecurringTransaction/RecurringTransaction+Extensions.swift
   ledger/CoreData/CDTransaction/CDTransaction+CoreDataClass.swift
   ledger/CoreData/CDTransaction/CDTransaction+CoreDataProperties.swift
   ledger/CoreData/CDTransaction/CDTransaction+Extensions.swift
   ledger/CoreData/JournalEntry/JournalEntry+CoreDataClass.swift
   ledger/CoreData/JournalEntry/JournalEntry+CoreDataProperties.swift
   ledger/CoreData/JournalEntry/JournalEntry+Extensions.swift
   ```

   Also add the `Ledger.xcdatamodeld` model to the widget target:
   - Select `Ledger.xcdatamodeld` in the navigator → in the **File Inspector** on
     the right, check **Target Membership → LedgerWidget**

3. **App Group for the widget**: Select the **LedgerWidget** target →
   **Signing & Capabilities → + Capability → App Groups** → add `group.ledger`

---

## 9. App Icon

1. Go to [appicon.co](https://appicon.co), upload a 1024×1024 PNG, download the
   generated set.
2. In Xcode, click `Assets.xcassets` → delete the placeholder `AppIcon` set →
   drag the downloaded `AppIcon.appiconset` folder in.

See `LedgerWidget/AppIcon.md` for design guidelines.

---

## 10. Privacy Policy (GitHub Pages)

A real privacy policy page is at `docs/privacy.html` and is already linked in
`SettingsView.swift` as `https://hatchatcha9.github.io/ledger/privacy.html`.

To make it live:

1. Push the repo to GitHub (or your existing `ledger` repo at github.com/hatchatcha9/ledger).
2. On GitHub → **Settings → Pages** → Source: **Deploy from a branch** → **main / docs**.
3. The page is live at `https://hatchatcha9.github.io/ledger/privacy.html` in ~1 min.
4. Verify the link works before submitting to App Store Connect.

## 10a. Privacy Manifest (required since May 2024)

`App/PrivacyInfo.xcprivacy` is already in the source tree. You must add it to the
**Ledger** target in Xcode so it is bundled with the app:

1. In the Xcode Project Navigator, right-click the `App/` group →
   **Add Files to "Ledger"…**
2. Select `App/PrivacyInfo.xcprivacy`. Set **Add to targets: ✅ Ledger**.
3. Build once to confirm no warnings about missing privacy manifest.

---

## 11. Build & verify

Press **⌘B**. The most likely issues and fixes:

| Issue | Fix |
|-------|-----|
| `'xxx' is already defined` | Two files both declare the same type — delete the duplicate (usually the Xcode-generated default file) |
| `Cannot find type 'xxx'` | That file wasn't added to the target — add it via Step 4 |
| CoreData model mismatch on launch | Delete the app from the simulator and re-run |
| Widget doesn't show data | Confirm App Group IDs match in both targets (Step 7 & 8) |

---

## 12. App Store Connect setup

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. **My Apps → +** → New App
   - Platform: iOS
   - Name: `Ledger — Finance & Portfolio`
   - Bundle ID: the one from Step 1
   - SKU: `ledger-ios-1`
3. Fill in:
   - **Description**: "Track accounts, investments, and trades in one place. Live
     prices, charts, recurring transactions, budgets, and a trading journal —
     all stored privately on your device."
   - **Keywords**: finance, budget, portfolio, trading journal, net worth, crypto, investments
   - **Support URL**: your privacy policy URL
   - **Privacy Policy URL**: same page as Step 10
4. **Age Rating**: 4+
5. Upload **screenshots** for iPhone 6.9" (iPhone 16 Pro Max) — simulator
   screenshots are fine for initial review:
   - Dashboard with chart
   - Accounts list
   - Portfolio with live prices
   - Journal entry
   - Settings / Budgets

---

## 13. Archive & submit

1. Select **Any iOS Device (arm64)** as the destination
2. **Product → Archive**
3. In the Organizer: **Distribute App → App Store Connect → Upload**
4. Back in App Store Connect: **Add for Review → Submit**

Review typically takes 1–3 days.

---

## Checklist summary

- [ ] Xcode project created (Step 1)
- [ ] Source files copied to Mac (Step 2)
- [ ] Xcode's default ContentView.swift + LedgerApp.swift deleted (Step 3)
- [ ] All source folders added to Ledger target (Step 4)
- [ ] `Ledger.xcdatamodeld` added to Ledger target (Step 5)
- [ ] `NSFaceIDUsageDescription` in Info.plist (Step 6)
- [ ] App Group `group.ledger` on Ledger target (Step 7)
- [ ] LedgerWidget target created and shared files added (Step 8)
- [ ] App Group `group.ledger` on LedgerWidget target (Step 8)
- [ ] App icon imported (Step 9)
- [ ] GitHub Pages deployed; privacy policy URL live (Step 10)
- [ ] `PrivacyInfo.xcprivacy` added to Ledger target (Step 10a)
- [ ] `Core/Services/Secrets.swift` created from `Secrets.swift.example` (one-time)
- [ ] Build passes ⌘B with no errors (Step 11)
- [ ] App Store Connect listing filled in (Step 12)
- [ ] Screenshots uploaded (Step 12)
- [ ] Archived and submitted (Step 13)
