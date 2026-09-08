"""Interfaz grafica para convertir PDF en chunks JSONL."""

from __future__ import annotations

import queue
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from chunker import MODEL_NAME, OUTPUT_DIMENSIONS, transform_pdf


class TransformationApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("Transformacion de PDF para RAG")
        self.geometry("780x560")
        self.minsize(680, 500)
        self.pdf_files: list[Path] = []
        self.messages: queue.Queue[tuple[str, object]] = queue.Queue()

        base_dir = Path(__file__).resolve().parent
        self.output_var = tk.StringVar(value=str(base_dir / "salida"))
        self.max_tokens_var = tk.IntVar(value=700)
        self.overlap_var = tk.IntVar(value=80)
        self.status_var = tk.StringVar(value="Selecciona uno o varios archivos PDF.")
        self._build_ui()
        self.after(100, self._drain_messages)

    def _build_ui(self) -> None:
        style = ttk.Style(self)
        style.configure("Title.TLabel", font=("Segoe UI", 17, "bold"))
        style.configure("Hint.TLabel", foreground="#505a66")

        root = ttk.Frame(self, padding=22)
        root.pack(fill="both", expand=True)
        ttk.Label(root, text="PDF a chunks para embeddings", style="Title.TLabel").pack(anchor="w")
        ttk.Label(
            root,
            text=f"Salida JSONL preparada para {MODEL_NAME} ({OUTPUT_DIMENSIONS} dimensiones).",
            style="Hint.TLabel",
        ).pack(anchor="w", pady=(3, 18))

        file_frame = ttk.LabelFrame(root, text="1. Documentos", padding=12)
        file_frame.pack(fill="both", expand=True)
        buttons = ttk.Frame(file_frame)
        buttons.pack(fill="x")
        ttk.Button(buttons, text="Agregar PDF", command=self._choose_pdfs).pack(side="left")
        ttk.Button(buttons, text="Quitar seleccion", command=self._remove_selected).pack(side="left", padx=8)
        self.file_list = tk.Listbox(file_frame, height=7, selectmode="extended")
        self.file_list.pack(fill="both", expand=True, pady=(10, 0))

        options = ttk.LabelFrame(root, text="2. Configuracion", padding=12)
        options.pack(fill="x", pady=12)
        ttk.Label(options, text="Carpeta de salida:").grid(row=0, column=0, sticky="w")
        ttk.Entry(options, textvariable=self.output_var).grid(row=0, column=1, sticky="ew", padx=8)
        ttk.Button(options, text="Examinar", command=self._choose_output).grid(row=0, column=2)
        ttk.Label(options, text="Tokens maximos:").grid(row=1, column=0, sticky="w", pady=(10, 0))
        ttk.Spinbox(options, from_=100, to=3000, increment=50, textvariable=self.max_tokens_var, width=10).grid(
            row=1, column=1, sticky="w", padx=8, pady=(10, 0)
        )
        ttk.Label(options, text="Solapamiento:").grid(row=1, column=1, sticky="w", padx=(145, 0), pady=(10, 0))
        ttk.Spinbox(options, from_=0, to=500, increment=10, textvariable=self.overlap_var, width=8).grid(
            row=1, column=1, sticky="w", padx=(255, 0), pady=(10, 0)
        )
        options.columnconfigure(1, weight=1)

        action = ttk.Frame(root)
        action.pack(fill="x")
        self.progress = ttk.Progressbar(action, mode="determinate")
        self.progress.pack(side="left", fill="x", expand=True)
        self.process_button = ttk.Button(action, text="Convertir PDF", command=self._start)
        self.process_button.pack(side="right", padx=(12, 0))
        ttk.Label(root, textvariable=self.status_var, style="Hint.TLabel").pack(anchor="w", pady=(8, 0))

    def _choose_pdfs(self) -> None:
        selected = filedialog.askopenfilenames(title="Seleccionar PDF", filetypes=[("PDF", "*.pdf")])
        existing = {str(path).lower() for path in self.pdf_files}
        for name in selected:
            path = Path(name)
            if str(path).lower() not in existing:
                self.pdf_files.append(path)
                self.file_list.insert("end", str(path))
                existing.add(str(path).lower())

    def _remove_selected(self) -> None:
        for index in reversed(self.file_list.curselection()):
            self.file_list.delete(index)
            del self.pdf_files[index]

    def _choose_output(self) -> None:
        selected = filedialog.askdirectory(title="Carpeta de salida", initialdir=self.output_var.get())
        if selected:
            self.output_var.set(selected)

    def _start(self) -> None:
        if not self.pdf_files:
            messagebox.showwarning("Faltan documentos", "Selecciona al menos un PDF.")
            return
        try:
            max_tokens = int(self.max_tokens_var.get())
            overlap = int(self.overlap_var.get())
            if max_tokens < 100 or overlap < 0 or overlap >= max_tokens:
                raise ValueError
        except (ValueError, tk.TclError):
            messagebox.showerror("Configuracion invalida", "Revisa el tamano y el solapamiento.")
            return

        self.process_button.configure(state="disabled")
        self.progress.configure(maximum=len(self.pdf_files), value=0)
        self.status_var.set("Iniciando conversion...")
        worker = threading.Thread(
            target=self._process,
            args=(list(self.pdf_files), Path(self.output_var.get()), max_tokens, overlap),
            daemon=True,
        )
        worker.start()

    def _process(self, files: list[Path], output: Path, max_tokens: int, overlap: int) -> None:
        errors: list[str] = []
        total_chunks = 0
        warnings: list[str] = []
        for index, pdf in enumerate(files, start=1):
            try:
                _, _, count, low_text_pages = transform_pdf(
                    pdf, output, max_tokens, overlap, lambda text: self.messages.put(("status", text))
                )
                total_chunks += count
                if low_text_pages:
                    warnings.append(f"{pdf.name}: paginas con poco texto {low_text_pages}")
            except Exception as exc:  # La interfaz debe continuar con los demas archivos.
                errors.append(f"{pdf.name}: {exc}")
            self.messages.put(("progress", index))
        self.messages.put(("done", (total_chunks, errors, warnings, output)))

    def _drain_messages(self) -> None:
        try:
            while True:
                kind, payload = self.messages.get_nowait()
                if kind == "status":
                    self.status_var.set(str(payload))
                elif kind == "progress":
                    self.progress.configure(value=int(payload))
                elif kind == "done":
                    chunks, errors, warnings, output = payload
                    self.process_button.configure(state="normal")
                    self.status_var.set(f"Finalizado: {chunks} chunks creados.")
                    detail = f"Se crearon {chunks} chunks en:\n{output}"
                    if warnings:
                        detail += "\n\nAdvertencias:\n" + "\n".join(warnings)
                    if errors:
                        detail += "\n\nErrores:\n" + "\n".join(errors)
                        messagebox.showwarning("Conversion finalizada", detail)
                    else:
                        messagebox.showinfo("Conversion finalizada", detail)
        except queue.Empty:
            pass
        self.after(100, self._drain_messages)


if __name__ == "__main__":
    TransformationApp().mainloop()

