"""Majesty-styled tkinter front end for the QoL bundle."""

from __future__ import annotations

from pathlib import Path
import queue
import threading
import tkinter as tk
from tkinter import filedialog, font as tkfont, messagebox, ttk
import webbrowser

from qol_installer import UTILITIES, Utility, detect_utility, is_game_exe, resolve_game_exe, run_utility


COLORS = {
    "window": "#12100c", "surface": "#1e1a14", "surface_alt": "#282016",
    "border": "#4a4038", "gold": "#d8a058", "gold_lit": "#eac278",
    "gold_text": "#1a1206", "text": "#ece3d0", "muted": "#a89880",
    "faint": "#7a6c5a", "success": "#8fbf7a", "warning": "#e0b060",
    "error": "#d97a62", "input": "#0d0b08",
}

PATCH_DETAILS_URL = "https://github.com/Phantomstar721/majesty-gold-hd-qol-utilities"


def enable_dpi_awareness() -> None:
    try:
        import ctypes
        ctypes.windll.shcore.SetProcessDpiAwareness(1)
    except (AttributeError, OSError, ImportError):
        pass


class InstallerApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        root.title("Majesty Gold HD QoL Utilities")
        # Keep all nine utility cards and the footer buttons visible on first
        # launch, including at the common 125% Windows display scale.
        root.geometry("980x960")
        root.minsize(880, 900)
        root.configure(background=COLORS["window"])
        self.font = self._font(("Segoe UI", "Tahoma"), "TkDefaultFont")
        self.heading = self._font(("Georgia", "Palatino Linotype", "Segoe UI Semibold"), self.font)
        self.game_var = tk.StringVar(value=str(resolve_game_exe() or ""))
        self.game_status = tk.StringVar(value="Checking selected executable…")
        self.activity = tk.StringVar(value="Ready")
        self.states = {utility.key: tk.StringVar(value="Checking…") for utility in UTILITIES}
        self.buttons: dict[str, tuple[ttk.Button, ttk.Button]] = {}
        self.messages: queue.Queue[tuple[str, object]] = queue.Queue()
        self.busy = False
        self._styles()
        self._build()
        self.root.after(100, self._poll)
        self.refresh()

    def _font(self, candidates: tuple[str, ...], fallback: str) -> str:
        available = {name.lower() for name in tkfont.families(self.root)}
        return next((name for name in candidates if name.lower() in available), fallback)

    def _styles(self) -> None:
        style = ttk.Style(self.root)
        style.theme_use("clam")
        style.configure("Dark.TEntry", fieldbackground=COLORS["input"], foreground=COLORS["text"], bordercolor=COLORS["border"], insertcolor=COLORS["gold"])
        style.configure("Quiet.TButton", background=COLORS["surface_alt"], foreground=COLORS["text"], bordercolor=COLORS["border"], padding=(12, 7), font=(self.font, 9, "bold"))
        style.map("Quiet.TButton", background=[("active", "#33291b"), ("disabled", COLORS["surface"])], foreground=[("disabled", COLORS["faint"])])
        style.configure("Gold.TButton", background=COLORS["gold"], foreground=COLORS["gold_text"], bordercolor=COLORS["gold_lit"], padding=(15, 8), font=(self.font, 9, "bold"))
        style.map("Gold.TButton", background=[("active", COLORS["gold_lit"]), ("disabled", "#8a6f42")])

    def _build(self) -> None:
        outer = tk.Frame(self.root, bg=COLORS["window"], padx=28, pady=18)
        outer.pack(fill="both", expand=True)
        tk.Label(outer, text="MAJESTY GOLD HD", bg=COLORS["window"], fg=COLORS["gold"], font=(self.heading, 11, "bold")).pack(anchor="w")
        tk.Label(outer, text="Quality-of-Life Utilities", bg=COLORS["window"], fg=COLORS["text"], font=(self.heading, 25, "bold")).pack(anchor="w", pady=(2, 2))
        tk.Label(outer, text="Choose exactly which improvements to apply to your copy of Majesty.", bg=COLORS["window"], fg=COLORS["muted"], font=(self.font, 10)).pack(anchor="w", pady=(0, 14))

        location = tk.Frame(outer, bg=COLORS["surface"], highlightbackground=COLORS["border"], highlightthickness=1, padx=15, pady=12)
        location.pack(fill="x", pady=(0, 12))
        tk.Label(location, text="TARGET EXECUTABLE", bg=COLORS["surface"], fg=COLORS["faint"], font=(self.font, 8, "bold")).grid(row=0, column=0, sticky="w")
        location.columnconfigure(0, weight=1)
        self.entry = ttk.Entry(location, textvariable=self.game_var, style="Dark.TEntry", font=(self.font, 10))
        self.entry.grid(row=1, column=0, sticky="ew", pady=(5, 3))
        self.browse = ttk.Button(location, text="Choose EXE", style="Quiet.TButton", command=self._choose)
        self.browse.grid(row=1, column=1, padx=(10, 0))
        self.game_label = tk.Label(location, textvariable=self.game_status, bg=COLORS["surface"], fg=COLORS["muted"], font=(self.font, 8))
        self.game_label.grid(row=2, column=0, sticky="w")

        cards = tk.Frame(outer, bg=COLORS["window"])
        cards.pack(fill="both", expand=True)
        cards.columnconfigure(0, weight=1)
        for row, utility in enumerate(UTILITIES):
            self._card(cards, utility, row)

        footer = tk.Frame(outer, bg=COLORS["window"])
        footer.pack(fill="x", pady=(10, 0))
        self.activity_label = tk.Label(footer, textvariable=self.activity, bg=COLORS["window"], fg=COLORS["muted"], font=(self.font, 9))
        self.activity_label.pack(side="left")
        details = tk.Label(
            footer, text="Full Patch Details", bg=COLORS["window"], fg=COLORS["gold"],
            activebackground=COLORS["window"], activeforeground=COLORS["gold_lit"],
            cursor="hand2", font=(self.font, 9, "underline"),
        )
        details.pack(side="left", padx=(18, 0))
        details.bind("<Button-1>", lambda _event: webbrowser.open(PATCH_DETAILS_URL))
        self.uninstall_all = ttk.Button(footer, text="Uninstall All", style="Quiet.TButton", command=lambda: self._all("uninstall"))
        self.uninstall_all.pack(side="right")
        self.install_all = ttk.Button(footer, text="Install All", style="Gold.TButton", command=lambda: self._all("install"))
        self.install_all.pack(side="right", padx=(0, 9))

    def _card(self, parent: tk.Widget, utility: Utility, row: int) -> None:
        card = tk.Frame(parent, bg=COLORS["surface"], highlightbackground=COLORS["border"], highlightthickness=1, padx=14, pady=9)
        card.grid(row=row, column=0, sticky="ew", pady=(0, 6))
        card.columnconfigure(0, weight=1)
        tk.Label(card, text=utility.name, bg=COLORS["surface"], fg=COLORS["text"], font=(self.font, 10, "bold")).grid(row=0, column=0, sticky="w")
        tk.Label(card, text=utility.description, bg=COLORS["surface"], fg=COLORS["muted"], font=(self.font, 8), anchor="w").grid(row=1, column=0, sticky="w", pady=(3, 0))
        status = tk.Label(card, textvariable=self.states[utility.key], bg=COLORS["surface"], fg=COLORS["faint"], font=(self.font, 8, "bold"), width=12)
        status.grid(row=0, column=1, rowspan=2, padx=(8, 10))
        install = ttk.Button(card, text="Install", style="Gold.TButton", command=lambda u=utility: self._one(u, "install"))
        install.grid(row=0, column=2, rowspan=2, padx=(0, 7))
        uninstall = ttk.Button(card, text="Uninstall", style="Quiet.TButton", command=lambda u=utility: self._one(u, "uninstall"))
        uninstall.grid(row=0, column=3, rowspan=2)
        self.buttons[utility.key] = (install, uninstall)

    def _choose(self) -> None:
        selected = filedialog.askopenfilename(title="Select MajestyHD.exe", filetypes=(("Majesty executable", "MajestyHD.exe"), ("Executable files", "*.exe")))
        if selected:
            self.game_var.set(selected)
            self.refresh()

    def _target(self, show_error: bool = True) -> Path | None:
        target = Path(self.game_var.get().strip())
        if not is_game_exe(target):
            if show_error:
                messagebox.showerror("MajestyHD.exe not found", "Choose a valid file named MajestyHD.exe.")
            return None
        return target

    def refresh(self) -> None:
        if self.busy:
            return
        target = self._target(False)
        if not target:
            self.game_status.set("MajestyHD.exe was not detected — choose it manually")
            self.game_label.configure(fg=COLORS["error"])
            for state in self.states.values(): state.set("Unavailable")
            self._enabled(False)
            return
        self.game_status.set("Detected · inspecting installed utilities")
        self.game_label.configure(fg=COLORS["success"])
        self._enabled(False)
        threading.Thread(target=self._detect_worker, args=(target,), daemon=True).start()

    def _detect_worker(self, target: Path) -> None:
        results = {utility.key: detect_utility(utility, target) for utility in UTILITIES}
        self.messages.put(("detected", results))

    def _one(self, utility: Utility, action: str) -> None:
        target = self._target()
        if target:
            self._start([(utility, action)], target, f"{action.title()}ing {utility.name}…")

    def _all(self, action: str) -> None:
        target = self._target()
        if not target:
            return
        jobs = [(utility, action) for utility in (UTILITIES if action == "install" else reversed(UTILITIES))]
        self._start(jobs, target, f"{action.title()}ing all utilities…")

    def _start(self, jobs: list[tuple[Utility, str]], target: Path, label: str) -> None:
        self.busy = True
        self._enabled(False)
        self.activity.set(label)
        self.activity_label.configure(fg=COLORS["gold"])
        threading.Thread(target=self._work, args=(jobs, target), daemon=True).start()

    def _work(self, jobs: list[tuple[Utility, str]], target: Path) -> None:
        logs: list[str] = []
        for utility, action in jobs:
            result = run_utility(utility, action, target)
            logs.append(f"== {utility.name} ==\n{result.stdout}{result.stderr}".strip())
            if result.returncode:
                self.messages.put(("failed", (utility.name, result.returncode, "\n\n".join(logs))))
                return
        self.messages.put(("done", "\n\n".join(logs)))

    def _enabled(self, enabled: bool) -> None:
        state = "normal" if enabled else "disabled"
        self.entry.configure(state=state); self.browse.configure(state=state)
        self.install_all.configure(state=state); self.uninstall_all.configure(state=state)
        for install, uninstall in self.buttons.values():
            install.configure(state=state); uninstall.configure(state=state)

    def _poll(self) -> None:
        try:
            while True:
                kind, payload = self.messages.get_nowait()
                if kind == "detected":
                    results = payload
                    for utility in UTILITIES:
                        status, detail = results[utility.key]
                        self.states[utility.key].set(detail if status != "error" else "Needs attention")
                        install, uninstall = self.buttons[utility.key]
                        install.configure(text="Installed" if status == "installed" else "Install")
                        if status == "installed": install.configure(state="disabled")
                    self._enabled(True)
                    for utility in UTILITIES:
                        if results[utility.key][0] == "installed": self.buttons[utility.key][0].configure(state="disabled")
                    self.game_status.set("Detected · status is up to date")
                elif kind == "done":
                    self.busy = False
                    self.activity.set("Finished successfully")
                    self.activity_label.configure(fg=COLORS["success"])
                    self.refresh()
                elif kind == "failed":
                    name, code, log = payload
                    self.busy = False
                    self.activity.set(f"Could not finish {name}")
                    self.activity_label.configure(fg=COLORS["error"])
                    messagebox.showerror("Utility could not be changed", f"{name} exited with code {code}.\n\n{log[-3500:]}")
                    self.refresh()
        except queue.Empty:
            pass
        self.root.after(100, self._poll)


def main() -> int:
    enable_dpi_awareness()
    root = tk.Tk()
    InstallerApp(root)
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
