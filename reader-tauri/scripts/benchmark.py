"""Measure process launch to visible bookshelf cards via loopback DevTools."""
import argparse
import ctypes
import json
import os
import socket
import subprocess
import time
import urllib.request
from pathlib import Path

import websocket


def run(executable, kind, read=False):
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    switch = f"--remote-debugging-port={port}"
    args = [str(executable)]
    env = os.environ.copy()
    if kind == "electron":
        args.append(switch)
        if env.get("READER_BENCH_PROFILE"):
            args.append("--user-data-dir="+env["READER_BENCH_PROFILE"])
    else:
        env["WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS"] = switch
    start = time.perf_counter()
    proc = subprocess.Popen(args, env=env, stdout=None if env.get("READER_BENCH_LOG") else subprocess.DEVNULL, stderr=None if env.get("READER_BENCH_LOG") else subprocess.DEVNULL)
    ws = None
    try:
        while time.perf_counter() - start < 30:
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list", timeout=.5) as res:
                    pages = json.load(res)
                page = next(p for p in pages if p["type"] == "page" and p["url"] != "about:blank")
                ws = websocket.create_connection(page["webSocketDebuggerUrl"], suppress_origin=True, timeout=3)
                break
            except (OSError, StopIteration, ValueError, websocket.WebSocketException):
                time.sleep(.02)
        if not ws:
            raise RuntimeError("Debug endpoint unavailable")

        ws.send(json.dumps({"id":99,"method":"Page.enable"}))
        def evaluate(expression):
            ws.send(json.dumps({"id":1,"method":"Runtime.evaluate","params":{"expression":expression,"returnByValue":True}}))
            while True:
                reply=json.loads(ws.recv())
                if reply.get("method")=="Page.javascriptDialogOpening":
                    raise RuntimeError(reply["params"]["message"])
                if reply.get("id")==1:
                    return reply.get("result",{}).get("result",{}).get("value")

        count = 0
        while time.perf_counter() - start < 30:
            count = evaluate("Array.from(document.querySelectorAll('.book-card')).filter(e=>e.getBoundingClientRect().height>0).length")
            if count:
                break
            time.sleep(.02)
        if not count:
            raise RuntimeError("Bookshelf did not render")
        elapsed = round((time.perf_counter()-start)*1000)
        print(kind, elapsed, "ms", count, "books",flush=True)
        if read:
            evaluate("(Array.from(document.querySelectorAll('.book-card')).find(b=>b.querySelector('.book-title')?.textContent.includes('逻辑学入门')) || document.querySelector('.book-card')).click()")
            ws.close()
            for _ in range(150):
                with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list", timeout=1) as response:
                    target = next((t for t in json.load(response) if t["type"]=="page" and "bookId=" in t["url"]), None)
                if target:
                    ws = websocket.create_connection(target["webSocketDebuggerUrl"],suppress_origin=True,timeout=5)
                    break
                time.sleep(.1)
            else:
                raise RuntimeError("Independent reading window did not open")
            for _ in range(300):
                content=evaluate("Array.from(document.querySelectorAll('#viewer iframe')).some(f=>f.contentDocument?.body?.children.length)")
                if content:
                    print("Verified EPUB document",content,flush=True)
                    break
                time.sleep(.1)
            else:
                raise RuntimeError("No EPUB text rendered")
            evaluate("Array.from(document.querySelectorAll('.tabs button')).find(b=>b.textContent.trim()==='目录')?.click()")
            chapters=evaluate("document.querySelectorAll('.sidebar-content li button').length")
            if chapters and chapters>1:
                evaluate("let links=document.querySelectorAll('.sidebar-content li button');links[Math.floor(links.length/2)].click()")
                for _ in range(150):
                    length=evaluate("Math.max(0,...Array.from(document.querySelectorAll('#viewer iframe'),f=>f.contentDocument?.body?.innerText?.trim()?.length || 0))")
                    if length and length>100:
                        print("Verified chapter navigation:",chapters,"entries,",length,"text characters",flush=True)
                        break
                    time.sleep(.1)
                else:
                    raise RuntimeError("Chapter navigation did not render body text")
        return elapsed
    finally:
        if ws:
            ws.close()
        user32 = ctypes.windll.user32
        def close(hwnd, unused):
            pid = ctypes.c_ulong()
            user32.GetWindowThreadProcessId(hwnd,ctypes.byref(pid))
            if pid.value == proc.pid:
                user32.PostMessageW(hwnd,0x10,0,0)
            return True
        user32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool,ctypes.c_void_p,ctypes.c_void_p)(close),0)
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.terminate()
            proc.wait()


if __name__ == "__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("kind", choices=["electron","tauri"])
    parser.add_argument("exe", type=Path)
    parser.add_argument("--read", action="store_true")
    opts=parser.parse_args()
    run(opts.exe.resolve(),opts.kind,opts.read)
