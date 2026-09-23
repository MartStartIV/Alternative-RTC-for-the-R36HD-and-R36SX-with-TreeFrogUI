# 🕒 Alternative RTC Solution for R36HD / R36SX

A software-based Real-Time Clock (RTC) workaround designed for clone handheld consoles lacking physical hardware.

---

## 📌 Project Overview
This project provides an **alternative RTC solution** tailored specifically for the **R36HD** and **R36SX** clone handhelds. It is fully compatible with:
*   **TreeFrogUI** developed by *tzubertowski*.
*   Devices already using the **Fix Adapter 0.07** (where this solution is already included natively).

## ⚠️ Compatibility & Limitations
*   **SF3000 & Other Devices:** This solution may **not work out-of-the-box** on the SF3000 or similar consoles. It will likely require code modifications or adaptations.
*   **Older Firmware Versions:** While it *might* function on older builds of TreeFrogUI, compatibility is **not guaranteed**. It has been strictly tested and verified from **version 1.4.0_q onwards**.

---

## 🚀 Release History

### **Version 0.001(01)** — *Initial Release*
*   Implemented the alternative software RTC workaround system to simulate clock functionality on supported clone devices.
*   *Function performed by:* **MartStartIV**
### **Version 0.002(15)**
*   A tool has been created for Windows 10 and 11 users to update the `time_save.txt` file at the root of the USB drive; this automatically applies the RTC modification simply by running a batch file so that it can subsequently be read and implemented by the clone console.
*   Support has been added for reading the `time_save.txt` file from a USB drive (by connecting the same drive to the R36HD or R36SX clone console running TreeFrogUI) to facilitate subsequent RTC updates from Windows 10/11 (requires running a batch script).
*   The .sh code has been optimized for better performance on the R36HD and R36SX with TreeFrogUI or the 0.07 fix adapter.
*   *Function performed by:* **MartStartIV**
---
