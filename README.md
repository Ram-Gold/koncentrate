# 🍅 Koncentrate

A **KDE Plasma 6 widget** that combines a Pomodoro timer with a built-in To-Do List - so you can manage your tasks and stay focused, all from your desktop.

---

## ✨ Features

### Pomodoro Timer
- **Three modes** — Pomodoro (Focus), Short Break, and Long Break
- **Phase pills** at the top let you jump between modes instantly
- **+1 / -1 minute** controls to adjust time on the fly
- **Skip** button to move to the next phase early
- **Chime notification** when a session ends (configurable)
- Visual **progress arc** around the timer that reflects the current phase color

### To-Do List
- Add standalone **tasks** or organize them into **groups**
- **Collapse/expand** groups to keep things tidy
- **Drag and drop** to reorder tasks and groups
- **Completion tracking** — see your progress at a glance (e.g. `0/2`)
- **Trash** button to clear all completed tasks at once
- Inline **editing** for task and group names

---

## 🖥️ Requirements

- KDE Plasma 6
- Qt 6 with QtQuick, QtMultimedia
- Kirigami 2

---

## 🚀 Installation

1. Clone or download this repository.
2. Place the widget folder in your Plasma plasmoids directory:
   ```
   ~/.local/share/plasma/plasmoids/
   ```
3. Right-click your desktop → **Add Widgets** → search for **Koncentrate**.

---

## ⚙️ Configuration

Right-click the widget and select **Configure** to customize:
- Focus, Short Break, and Long Break durations
- Number of sessions before a Long Break
- Enable/disable the chime sound and set a custom audio file

---

## 📸 Preview

See the [screenshots](./screenshots) folder for visual demonstrations of the widget in action.

---

## 📄 License

This project is licensed under the [GNU General Public License v3.0](./LICENSE).

