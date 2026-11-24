# TouchBarTicker

A super lightweight, zero-dependency native macOS app that turns your MacBook Touch Bar into a live TV-style scrolling ticker for crypto and global stock exchanges.

## Features

- **Zero clutter**: No menu bar icon, no Dock icon, and no windows.
- **Launch & Quit**: Open **TouchBarTicker** from `/Applications` (or Spotlight) to start; tap **`✕`** on the far left of the Touch Bar to quit.
- **GPU-accelerated marquee**: Smooth scrolling with near-0% CPU usage between 30-second live price refreshes. Tap the ticker strip to pause/resume.
- **100% Touch Bar Settings (`⚙`)**:
  - **Far left `✕`**: Close Settings without saving changes.
  - **Left speed slider**: Drag and release to trigger a **2-second live preview** of the new scroll speed before automatically returning to Settings.
  - **Middle scrollable picker**: Swipe sideways to choose between **Crypto**, **NASDAQ**, **NYSE**, **S&P 500**, **Dow Jones**, **FTSE 100**, **Nikkei 225**, **TSX**, **DAX**, and **ASX 200**.
  - **Far right `Save`**: Persists your speed and selected feed and returns to the ticker.

## Build & Install

```bash
chmod +x build.sh
./build.sh            # Builds build/TouchBarTicker.app
./build.sh --install  # Builds and copies to /Applications/TouchBarTicker.app
```
