"""Compare rendered screens at an equal viewport against the current Electron build."""
import json, os, subprocess, socket, time, urllib.request, sys
from pathlib import Path
from tempfile import gettempdir
import websocket

def pages(port):
    with urllib.request.urlopen(f'http://127.0.0.1:{port}/json/list',timeout=1) as res:
        return [p for p in json.load(res) if p["type"]=="page" and p["url"]!="about:blank"]

def wait(test):
    end=time.monotonic()+35
    while time.monotonic()<end:
        try:
            result=test()
            if result:return result
        except (OSError,StopIteration,IndexError):pass
        time.sleep(.1)
    raise RuntimeError("Screen did not reach expected state")

class Page:
    def __init__(self,target):
        self.ws=websocket.create_connection(target["webSocketDebuggerUrl"],suppress_origin=True,timeout=20)
        self.seq=0
    def call(self,method,params):
        self.seq+=1
        self.ws.send(json.dumps(dict(id=self.seq,method=method,params=params)))
        while True:
            r=json.loads(self.ws.recv())
            if r.get('id')==self.seq:return r['result']
    def js(self,s):
        r=self.call('Runtime.evaluate',dict(expression=s,returnByValue=True,awaitPromise=True))
        if 'exceptionDetails' in r:raise RuntimeError(r['result'].get('description',str(r)))
        return r['result'].get('value')
    def capture(self, name):
        import base64
        folder=os.environ.get('READER_UI_EVIDENCE')
        if folder:
            dest=Path(folder)
            dest.mkdir(parents=True,exist_ok=True)
            self.call('Page.bringToFront',{})
            data=self.call('Page.captureScreenshot',{'format':'png','fromSurface':False})['data']
            (dest/(name+'.png')).write_bytes(base64.b64decode(data))
    def viewport(self):
        self.call('Emulation.setDeviceMetricsOverride',dict(width=1200,height=800,deviceScaleFactor=1,mobile=False))

geometry="""sels=>Object.fromEntries(sels.map(s=>{let e=document.querySelector(s); if(!e)return [s,null]; let r=e.getBoundingClientRect(),c=getComputedStyle(e); return [s,[r.x,r.y,r.width,r.height,c.fontSize,c.color,c.backgroundColor]]}))"""
def measure(kind,exe,baseline):
    with socket.socket() as sock:
        sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
    env=os.environ.copy()
    switch=f'--remote-debugging-port={port}'
    args=[exe]
    if kind=='electron':args.extend([baseline,switch,'--disable-gpu','--disable-backgrounding-occluded-windows','--user-data-dir='+os.environ.get('READER_BENCH_PROFILE',str(Path(gettempdir(),'epub-reader-bench-profile')))])
    else:
        env['WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS']=switch
        env['WEBVIEW2_USER_DATA_FOLDER']=str(Path(gettempdir(),'reader-tauri-ui-test-profile'))
    proc=subprocess.Popen(args,env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        t=wait(lambda:next(iter(pages(port))))
        shelf=Page(t)
        result_native = shelf.js("({width:innerWidth,height:innerHeight})")
        shelf.viewport()
        wait(lambda:shelf.js("document.querySelectorAll('.book-card').length"))
        result={'native':result_native,'methods':shelf.js('Object.keys(window.electronAPI).sort()')}
        shelf.call('DOM.enable',{})
        shelf.call('CSS.enable',{})
        doc=shelf.call('DOM.getDocument',{})['root']['nodeId']
        for selector in ['.btn-add-book','.book-title']:
            node=shelf.call('DOM.querySelector',{'nodeId':doc,'selector':selector})['nodeId']
            fonts=shelf.call('CSS.getPlatformFontsForNode',{'nodeId':node})['fonts']
            result['font '+selector]=[font['familyName'] for font in fonts]
        result['shelf']=shelf.js(f"({geometry})(['.sidebar','.btn-add-book','.books-grid','.book-card','.book-title','.btn-settings','.btn-login','.cloud-section'])")
        shelf.capture(kind+'-shelf')
        if kind=='tauri':
            assert shelf.js("Array.from(document.querySelectorAll('.book-card')).every(c=>c.querySelector('button.book-title') && (!c.querySelector('.book-badge') || c.querySelector('.book-badge').getBoundingClientRect().top >= c.querySelector('.book-cover').getBoundingClientRect().bottom))")
            shelf.call('Emulation.setDeviceMetricsOverride',dict(width=800,height=650,deviceScaleFactor=1,mobile=False))
            assert shelf.js("document.querySelector('.sort-select').getBoundingClientRect().right<=innerWidth")
            shelf.capture('tauri-shelf-narrow')
            shelf.viewport()
        shelf.js("document.querySelector('.btn-settings').click()")
        wait(lambda:shelf.js("!!document.querySelector('.settings-page')"))
        result['settings']=shelf.js(f"({geometry})(['.settings-page','.settings-header','.settings-section','.settings-item'])")
        shelf.capture(kind+'-settings')
        shelf.js("document.querySelector('.btn-back').click()")
        title=json.dumps(os.environ.get('READER_TEST_TITLE','逻辑学入门'))
        shelf.js(f"(Array.from(document.querySelectorAll('.book-card')).find(b=>b.textContent.includes({title})) || document.querySelector('.book-card')).click()")
        r=wait(lambda:next(x for x in pages(port) if x['id']!=t['id'] and 'bookId=' in x['url']))
        reader=Page(r);reader.viewport()
        wait(lambda:reader.js("!!document.querySelector('#viewer iframe')?.contentDocument?.body?.children.length"))
        result['reader']=reader.js(f"({geometry})(['.reader-toolbar','.sidebar','.toolbar-left','.tabs','.reader-main'])")
        reader.js("Array.from(document.querySelectorAll('.tabs button')).find(b=>b.textContent.trim()==='目录').click()")
        wait(lambda:reader.js("document.querySelectorAll('.sidebar-content li button').length>1"))
        # The reader restores the saved CFI asynchronously after the first iframe is ready.
        # A chapter selection made during restore can be superseded by that initial display.
        def select_sample():
            reader.js("(()=>{let links=document.querySelectorAll('.sidebar-content li button');links[Math.floor(links.length/2)].click()})()")
            for _ in range(15):
                time.sleep(.2)
                if reader.js("Array.from(document.querySelectorAll('#viewer iframe')).some(f=>f.contentDocument?.body?.innerText?.length>100)"):
                    return True
            return False
        wait(select_sample)
        reader.capture(kind+'-reader')
        if kind=='tauri':
            wait(lambda:reader.js("!!document.querySelector('.toc-link[aria-current]')"))
            reader.call('Emulation.setDeviceMetricsOverride',dict(width=800,height=650,deviceScaleFactor=1,mobile=False))
            reader.js("document.querySelector('.btn-dark-toggle').click()")
            assert reader.js("document.querySelector('.btn-dark-toggle').getAttribute('aria-pressed')==='true' && document.querySelector('.reader-toolbar .btn-settings').getBoundingClientRect().right<=innerWidth")
            reader.capture('tauri-reader-dark-narrow')
            reader.js("document.querySelector('.btn-dark-toggle').click()")
        return result
    finally:
        subprocess.run(['taskkill','/T','/PID',str(proc.pid),'/F'],capture_output=True)

if __name__=='__main__':
    results=[measure('electron',sys.argv[1],sys.argv[2]),measure('tauri',sys.argv[3],'')]
    for key, baseline in results[0].items():
        current=results[1][key]
        if key in ('shelf','settings','reader'):
            differences=[]
            for selector,expected in baseline.items():
                observed=current[selector]
                assert expected and observed, (key,selector)
                if selector in ('.books-grid','.book-card','.book-title','.toolbar-left','.reader-toolbar'):
                    continue  # The Tauri shelf grid and reading controls have their own layout.
                assert expected[4:]==observed[4:], (key,selector,'text or background style')
                differences.extend(abs(a-b) for a,b in zip(expected[:4],observed[:4]))
            delta=max(differences)
            assert delta<2, (key,delta)
            print(key, f'maximum measured difference {delta:.2f} CSS px')
        else:
            assert baseline==current, (key,baseline,current)
            print(key, 'MATCH')
