# **nano11 🔬**

A PowerShell script to build a heavily trimmed-down Windows 11 image.

## **Introduction**

Welcome to nano11, the next step in creating ultra-lightweight Windows 11 builds. This project provides a flexible and powerful PowerShell solution for creating custom, minimal installation images.

You can now use this script on **ANY Windows 11 release**, regardless of build, language, or architecture. This is made possible thanks to the improved scripting capabilities of PowerShell.

The goal of nano11 is to automate the build of a streamlined Windows 11 image. The script uses only built-in DISM capabilities and the official oscdimg.exe (downloaded automatically) to create a bootable ISO with no external binaries. An included unattended answer file helps bypass the Microsoft Account requirement during setup and enables compact installation by default. It's open-source, so feel free to modify and adapt it to your needs\!

## **☢️ Script Philosophy: The Core Builder**

This repository contains a single, powerful script: nano11.ps1. This is an **extreme experimental script** designed for creating a quick and dirty development testbed. It removes everything possible to get the smallest footprint, including the Windows Component Store (WinSxS), core services, and much more.

The resulting OS is **not serviceable**. This means you cannot add languages, drivers, or features, and you will not receive Windows Updates. It is intended only for testing, development, or embedded use in VMs where a minimal, static environment is required.

## **What is removed?**

The nano11.ps1 script is extremely aggressive. It removes:

* **All Bloatware Apps:** Clipchamp, News, Weather, Xbox, Office Hub, Solitaire, etc.  
* **Core System Components:**  
  * ⛔ **Windows Component Store (WinSxS)**  
  * ⛔ **Windows Update** (and its services)  
  * ⛔ **Windows Defender** (and its services)  
  * ⛔ Most **Drivers** (keeps VGA, Net, Storage only)  
  * ⛔ **All IMEs** (Asian languages)  
  * ⛔ Search, BitLocker, Biometrics, and Accessibility features  
  * ⛔ Most system services (including Audio)  
* **Other Components:**  
  * Microsoft Edge & OneDrive  
  * Internet Explorer & Tablet PC Math

⚠️ **Important:** You cannot add back features or languages in an image created with this script\!

## **Instructions**

1. **Download Windows 11** from the Microsoft website.  
2. **Mount the downloaded ISO** image by right-clicking it and selecting "Mount". Note the drive letter.  
3. **Open PowerShell as Administrator**.  
4. **Set the execution policy** for the current session by running this command:  
   Set-ExecutionPolicy Bypass \-Scope Process

5. **Navigate to the script's folder** and start it:  
   C:\\path\\to\\your\\nano11\\nano11.ps1

6. **Follow the prompts:** The script will ask for the drive letter of the mounted image and the edition (SKU) you want to base your image on.  
7. **Sit back and relax\!** When completed, the new ISO will be in the same folder as the script.

## **Known Issues & Troubleshooting**

* **Stuck on Boot:** If your ISO hangs on the boot screen, a critical service or component was removed. The most likely culprits are the **Audio services** or the aggressive WinSxS trim. You may need to edit the script to be less aggressive for your specific hardware or Windows build.  
* **Installer Errors:** An error like 'autorun.dll' could not be loaded means a critical setup file was removed. This can happen with the aggressive sources folder cleanup. Add the missing file to the $dependencies list in the boot.wim section and rebuild.  
* **Remnants:** Although Edge is removed, some links may remain in the Settings app.  
* **Post-install Apps:** Outlook and Dev Home might try to reinstall themselves over time. The script attempts to block this, but it's an ongoing battle.

## **Future Features**

* Improved language and architecture detection.  
* More flexibility in what to keep and what to delete, possibly via a config file.  
* A GUI to make the process even easier.

And that's pretty much it for now\! Thanks for trying nano11 and let me know how you like it\!