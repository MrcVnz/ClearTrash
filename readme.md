# ClearTrash

<p align="center">
<img src="https://img.shields.io/badge/platform-Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white"/>
<img src="https://img.shields.io/badge/language-PowerShell-5391FE?style=for-the-badge&logo=powershell&logoColor=white"/>
<img src="https://img.shields.io/badge/script-Batch-4D4D4D?style=for-the-badge&logo=gnubash&logoColor=white"/>
<img src="https://img.shields.io/badge/interface-CLI-black?style=for-the-badge&logo=windows-terminal&logoColor=white"/>
<img src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge"/>
</p>

ClearTrash is a small Windows CLI cleanup tool written in **PowerShell**, with a **Batch launcher**.

I mainly created this project so people could study it.
The code is very straightforward, which makes it easier to understand how everything works.

The idea is simple: choose folders, pick how files should be deleted, and let the script handle the rest.

---

## Demo

<p align="center">
<img src="assets/demo.gif" width="700">
</p>

---

## Features

- interactive CLI menu
- choose folders to clean
- multiple deletion modes
- progress bar during cleanup
- pause / resume with keyboard input
- optional logging
- shows how much disk space was freed

---

## Cleaning modes

The tool currently supports different deletion strategies.

**Recycle Bin**

Files are moved to the Windows Recycle Bin.

**Permanent delete**

Files are removed directly from disk.

**Recycle + empty**

Files go to the Recycle Bin and the bin is emptied afterwards.

---

## Running the tool

Clone the repository:

```
git clone https://github.com/MrcVnz/ClearTrash.git
```

Enter the folder:

```
cd ClearTrash
```

Run the launcher in powershell:

```
.\ClearTrash.bat
```

Run the launcher in CMD:

```
ClearTrash.bat
```

The batch file simply launches the PowerShell script with the correct permissions.

---

### Why a `.bat` launcher?

The project includes a small `.bat` launcher to make the script easier to run.

It avoids common PowerShell execution policy issues and allows users to start the tool with a simple command or double-click, without needing to manually run the PowerShell script.

---

## Project structure

```
ClearTrash
│
├ ClearTrash.ps1
├ ClearTrash.bat
└ README.md
```

**ClearTrash.ps1**

Main script responsible for:

- CLI interface
- folder scanning
- deletion logic
- progress bar
- logging

**ClearTrash.bat**

Simple launcher that starts the PowerShell script.

---

## Why I built this project

I wanted to build a simple tool that could help people who are learning these languages.

It’s not exactly an easy thing for a beginner to create, but working on something like this helps you understand how the system behaves and how different parts of the machine interact.

Instead of writing small isolated scripts, I tried to build something that feels closer to a real utility.

---

## Things that could be improved

Some ideas for the future:

- preview mode (scan without deleting)
- more Windows cache locations
- configuration file
- better logging system

---

## License

MIT