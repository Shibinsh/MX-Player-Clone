# MX Player Clone (Flutter)

A modern Flutter Android video player inspired by MX Player, featuring dark/AMOLED themes, hardware-accelerated video decoding (fvp/libmpv), thumbnail caching, gesture controls (volume, brightness, seek, pinch-to-zoom), paired `.srt` subtitles, audio player, Wi-Fi LAN file transfer, and Room database-backed transfer history.

---

## 🚀 GitHub-ൽ നേരിട്ട് APK ബിൽഡ് ചെയ്യുന്ന വിധം (How to Build on GitHub Actions)

ഈ പ്രോജക്റ്റിൽ **GitHub Actions Workflow** പൂർണ്ണമായി സജ്ജീകരിച്ചിട്ടുണ്ട് (`.github/workflows/build.yml`).

1. ഈ ഫോൾഡറിലെ കോഡ് നിങ്ങളുടെ **GitHub Repository**-ലേക്ക് പുഷ് (Push) ചെയ്യുക.
2. GitHub-ൽ നിങ്ങളുടെ Repository തുറന്ന് മുകളിലുള്ള **Actions** ടാബിലേക്ക് പോവുക.
3. ഇടത് വശത്തുള്ള **Build Android APK** എന്ന വർക്ക്‌ഫ്ലോ തിരഞ്ഞെടുക്കുക.
4. **Run workflow** ബട്ടൺ അമർത്തുക (അല്ലെങ്കിൽ `main`/`master` ബ്രാഞ്ചിലേക്ക് push ചെയ്യുമ്പോൾ തനിയെ റൺ ആകും).
5. ബിൽഡ് പൂർത്തിയാകുമ്പോൾ **Artifacts** സെക്ഷനിൽ നിന്ന്:
   - **`MX-Player-Clone-Release-APK`** (നേരിട്ട് ഫോണിൽ ഇൻസ്റ്റാൾ ചെയ്യാൻ പറ്റുന്ന റിലീസ് എപികെ)
   - **`MX-Player-Clone-Debug-APK`**
   ഡൗൺലോഡ് ചെയ്ത് ഫോണിൽ ഇൻസ്റ്റാൾ ചെയ്യാം!

---

## 🛠️ ലോക്കൽ സിസ്റ്റത്തിൽ റൺ / ബിൽഡ് ചെയ്യുന്ന വിധം (Local Build)

### Requirements
- Flutter SDK (`stable` ചാനൽ - Flutter 3.27+)
- Java JDK 17
- Android SDK (API 34 / 35)

### Commands
```bash
# ഡിപെൻഡൻസികൾ ഇൻസ്റ്റാൾ ചെയ്യാൻ
flutter pub get

# പ്രോജക്റ്റ് ടെസ്റ്റ് / അനലൈസ് ചെയ്യാൻ
flutter analyze

# ഡീബഗ് മോഡിൽ റൺ ചെയ്യാൻ
flutter run

# റിലീസ് APK ബിൽഡ് ചെയ്യാൻ
flutter build apk --release
```

റിലീസ് APK ഈ പാത്തിൽ ലഭിക്കും: `build/app/outputs/flutter-apk/app-release.apk`
*(Debug Keystore ഉപയോഗിച്ച് സൈൻ ചെയ്തിരിക്കുന്നതിനാൽ ഏത് ആൻഡ്രോയിഡ് ഫോണിലും നേരിട്ട് ഇൻസ്റ്റാൾ ചെയ്യാം).*
