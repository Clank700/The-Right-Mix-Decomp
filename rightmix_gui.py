"""rightmix_gui - a small window around rightmix.py (tkinter ships with Python on Windows and macOS)."""
import os
import queue
import subprocess
import sys
import threading
import webbrowser

ROOT = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(ROOT, 'rightmix.py')


def main():
    import tkinter as tk
    from tkinter import filedialog, messagebox, scrolledtext, ttk

    win = tk.Tk()
    win.title('The Right Mix - build the ports from your own bartender.swf')
    win.geometry('820x560')
    q = queue.Queue()
    busy = {'proc': None}

    swf = tk.StringVar()
    want_win = tk.BooleanVar(value=os.name == 'nt')
    want_and = tk.BooleanVar(value=True)
    skip_match = tk.BooleanVar(value=False)
    lic = tk.BooleanVar(value=False)

    frm = ttk.Frame(win, padding=10)
    frm.pack(fill='both', expand=True)
    ttk.Label(frm, text='1. Your copy of the game (this program does not contain it):').grid(row=0, column=0, columnspan=3, sticky='w')
    ttk.Entry(frm, textvariable=swf).grid(row=1, column=0, columnspan=2, sticky='ew', padx=(0, 6))
    ttk.Button(frm, text='Browse...', command=lambda: swf.set(filedialog.askopenfilename(title='bartender.swf', filetypes=[('Flash movie', '*.swf'), ('All files', '*.*')]) or swf.get())).grid(row=1, column=2)

    ttk.Label(frm, text='2. Tools (Flutter, JDK, Android SDK):').grid(row=2, column=0, columnspan=3, sticky='w', pady=(10, 0))
    ttk.Button(frm, text='Check what is installed', command=lambda: start(['doctor'])).grid(row=3, column=0, sticky='w')
    ttk.Button(frm, text='Install missing tools', command=lambda: install()).grid(row=3, column=1, sticky='w')
    ttk.Checkbutton(frm, text='I have read and accept the Android SDK licenses', variable=lic).grid(row=4, column=0, columnspan=2, sticky='w')
    link = ttk.Label(frm, text='https://developer.android.com/studio/terms', foreground='blue', cursor='hand2')
    link.grid(row=4, column=2, sticky='w')
    link.bind('<Button-1>', lambda e: webbrowser.open('https://developer.android.com/studio/terms'))

    ttk.Label(frm, text='3. Build:').grid(row=5, column=0, sticky='w', pady=(10, 0))
    opts = ttk.Frame(frm)
    opts.grid(row=6, column=0, columnspan=3, sticky='w')
    cb = ttk.Checkbutton(opts, text='Windows 11 (.exe)', variable=want_win)
    cb.pack(side='left')
    if os.name != 'nt':
        cb.state(['disabled'])
        want_win.set(False)
    ttk.Checkbutton(opts, text='Android (.apk)', variable=want_and).pack(side='left', padx=12)
    ttk.Checkbutton(opts, text='skip the byte-identical rebuild check', variable=skip_match).pack(side='left')
    ttk.Button(frm, text='Build', command=lambda: build()).grid(row=7, column=0, sticky='w', pady=6)
    ttk.Button(frm, text='Stop', command=lambda: stop()).grid(row=7, column=1, sticky='w')
    log = scrolledtext.ScrolledText(frm, height=18, state='disabled', font=('Consolas', 9))
    log.grid(row=8, column=0, columnspan=3, sticky='nsew', pady=(6, 0))
    frm.columnconfigure(0, weight=1)
    frm.rowconfigure(8, weight=1)

    def append(text):
        log.configure(state='normal')
        log.insert('end', text)
        log.see('end')
        log.configure(state='disabled')

    def pump():
        try:
            while True:
                append(q.get_nowait())
        except queue.Empty:
            pass
        win.after(100, pump)

    def worker(args):
        q.put('\n> python rightmix.py %s\n' % ' '.join(args))
        p = subprocess.Popen([sys.executable, '-u', SCRIPT] + args, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, encoding='utf-8', errors='replace')
        busy['proc'] = p
        for line in p.stdout:
            q.put(line)
        p.wait()
        busy['proc'] = None
        q.put('\n[finished with exit code %d]\n' % p.returncode)

    def start(args):
        if busy['proc']:
            messagebox.showinfo('Busy', 'Something is already running.')
            return
        threading.Thread(target=worker, args=(args,), daemon=True).start()

    def need_swf():
        if not os.path.isfile(swf.get()):
            messagebox.showerror('bartender.swf', 'Choose your bartender.swf first.')
            return False
        return True

    def build():
        if not need_swf():
            return
        args = ['build', '--swf', swf.get()]
        if want_win.get() and not want_and.get():
            args.append('--windows')
        elif want_and.get() and not want_win.get():
            args.append('--android')
        elif not want_win.get() and not want_and.get():
            messagebox.showerror('Nothing selected', 'Tick Windows and/or Android.')
            return
        if skip_match.get():
            args.append('--skip-matching')
        start(args)

    def install():
        args = ['setup']
        if lic.get():
            args.append('--accept-android-licenses')
        start(args)

    def stop():
        if busy['proc']:
            busy['proc'].terminate()

    pump()
    append('Choose your bartender.swf, check the tools, then press Build.\n'
           'Everything is built on this PC from your own copy; nothing is uploaded.\n')
    win.mainloop()


if __name__ == '__main__':
    main()
