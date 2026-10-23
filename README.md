# Water Sort Puzzle for KOReader (`watersort.koplugin`)

An e-ink optimized, monochrome **Water Sort Puzzle** plugin built natively for [KOReader](https://github.com/koreader/koreader). 

Since e-ink devices (Kindle, Kobo, PocketBook, reMarkable, etc.) cannot display colors—and standard 16-level grayscale shades look nearly identical under different lighting conditions—this game replaces liquid colors with **10 distinct, procedurally rendered geometric patterns** paired with high-contrast number badges.

---

## Features

* **Designed for E-Ink Displays:** Uses crisp 1-bit/grayscale procedural patterns (`Blitbuffer`) with centered number badges (`1`–`9`, `0`) for instant readability with zero eye strain.
* **Unlimited Procedural Levels:** Powered by a deterministic Linear Congruential Generator (LCG) and Fisher-Yates multiset permutations. Level $X$ is always identical across all devices without requiring a heavy database of pre-made levels.
* **Progressive Difficulty Scaling:** Starts at $N = 4$ patterns (6 bottles) on early levels and gradually scales up to $N = 10$ patterns (12 bottles).
* **Full State Persistence:** Automatically saves your current level, exact bottle state, move counter, and undo history via `G_reader_settings`. Close the game to read your book and pick up right where you left off.
* **Ghosting & Refresh Optimization:** Uses fast partial `"ui"` refreshes when selecting and pouring bottles, and triggers a `"full"` e-ink flash refresh when loading new levels or exiting the game.
* **Zero External Assets:** Pure Lua implementation with DPI-aware scaling (`Screen:scaleBySize`), adapting cleanly to everything from 167 PPI Basic Kindles to 300 PPI Paperwhites, Scribes, and Kobos.

---

## E-Ink Pattern System

Instead of relying on colors, each liquid type is assigned a unique procedural texture and an alphanumeric label:

| Pattern ID | Classic Color Equivalent | Procedural E-Ink Texture | Badge |
| :---: | :--- | :--- | :---: |
| **1** | Red | Solid black fill | `1` |
| **2** | Blue | Alternating horizontal stripes | `2` |
| **3** | Green | Alternating vertical columns | `3` |
| **4** | Yellow | Spaced $3 \times 3$ polka dots | `4` |
| **5** | Purple | Alternating $4 \times 4$ checkerboard | `5` |
| **6** | Orange | Rising diagonal stripes (`//`) | `6` |
| **7** | Cyan | Falling diagonal stripes (`\\`) | `7` |
| **8** | Pink | Crosshatch grid (`#`) | `8` |
| **9** | Lime | Offset horizontal brick wall | `9` |
| **10** | Brown | Double concentric inner rectangular rings | `0` |

---

## How to Play

1. **Goal:** Sort the mixed patterns in the bottles until every bottle is either **completely empty** or **completely full of $4$ matching pattern units**.
2. **Selecting & Pouring:**
   * Tap any non-empty bottle to select it (an indicator bar will appear above it and the bottle will lift slightly).
   * Tap a target bottle to pour the top contiguous layer(s) of liquid into it.
3. **Pouring Rules:**
   * You can only pour from Bottle $A$ to Bottle $B$ if Bottle $B$ has empty space **and** is either completely empty or its top liquid unit matches the top liquid unit of Bottle $A$ ($\text{top}(A) = \text{top}(B)$).
   * If multiple contiguous units of the same pattern sit at the top of Bottle $A$, as many as will fit transfer together in a single move.
4. **Controls:**
   * **Undo:** Reverts your previous pour (supports unlimited undo steps back to the start of the level).
   * **Restart:** Resets the current level to its initial permutation.
   * **Level...:** Jump directly to any level number from $1$ to $\infty$.
   * **Skip:** Advance immediately to the next level.

---

## How Unlimited Level Generation Works

For a level with $N$ distinct patterns and bottle capacity $C = 4$, there is a multiset of $4N$ liquid units distributed across $N$ filled bottles (plus $E = 2$ empty helper bottles). The total number of distinct initial board configurations is given by the multiset permutation formula:

$$\text{Unique Combinations} = \frac{(4N)!}{(4!)^N \cdot N!}$$

* **Easy ($N = 4$ patterns):** $\frac{16!}{(24)^4 \cdot 4!} \approx 2.62 \times 10^6$ unique configurations.
* **Medium ($N = 8$ patterns):** $\frac{32!}{(24)^8 \cdot 8!} \approx 5.95 \times 10^{19}$ unique configurations.
* **Hard ($N = 10$ patterns):** $\frac{40!}{(24)^{10} \cdot 10!} \approx 3.55 \times 10^{27}$ unique configurations.

The generator seeds a deterministic PRNG using the level number, shuffles the $4N$ pool via Fisher-Yates, verifies that no bottle starts pre-solved ($4$ identical layers in one bottle), and appends $2$ empty helper bottles.

---

## Installation

### Method 1: Direct Download / USB Transfer
1. Download or clone this repository.
2. Connect your e-reader (Kindle, Kobo, PocketBook, etc.) to your computer via USB.
3. Copy the `watersort.koplugin` folder into your device's `koreader/plugins/` directory:
   ```text
   koreader/
   └── plugins/
       └── watersort.koplugin/
           ├── _meta.lua
           └── main.lua
   ```
4. Safely eject your device and **restart KOReader**.

### Method 2: Via SSH / Terminal on Device
```bash
cd /mnt/us/koreader/plugins/ # Adjust path for Kobo (.adds/koreader/plugins/)
git clone https://github.com/YOUR_USERNAME/watersort.koplugin.git
```

---

## Accessing the Game in KOReader

1. Open the KOReader top menu bar.
2. Tap the **Tools** icon (wrench and screwdriver).
3. Select **Water Sort Puzzle**.

---

## License

This project is licensed under the MIT License. Feel free to fork, modify, and submit pull requests!
