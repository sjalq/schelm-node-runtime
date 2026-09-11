import os,pty,subprocess,sys,termios,select,time,fcntl,struct,shutil
mode=sys.argv[1]; artifact=sys.argv[2]; master,slave=pty.openpty(); fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',24,80,0,0)); before=termios.tcgetattr(slave); node=os.environ.get('SCHELM_NODE_BIN') or shutil.which('node'); p=subprocess.Popen([node,'tests/pty/terminal-child.cjs',mode,artifact],stdin=slave,stdout=slave,stderr=slave,close_fds=True); out=b''; end=time.time()+5
if mode == 'input-replay':
 time.sleep(.5); os.write(master,b'\xff'); time.sleep(.1); os.write(master,b'\x04'); time.sleep(.1); os.write(master,b'\x04')
if mode == 'input-aba':
 time.sleep(1); os.kill(p.pid,2)
if mode in ('fanout-resize','limit-resize'):
 time.sleep(.5); fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',25,81,0,0)); os.kill(p.pid,28)
while time.time()<end and p.poll() is None:
 r,_,_=select.select([master],[],[],.1)
 if r:
  try:
   out+=os.read(master,4096)
   if mode=='input-aba' and b'ABA_READY' in out:
    mode='input-aba-fed'; os.write(master,b'\xff'); time.sleep(.1); os.write(master,b'\x04'); time.sleep(.1); os.write(master,b'\x04')
   if mode.startswith('resize-') and b'RESIZE_READY' in out:
    original=mode; mode='resize-fed'; time.sleep(1); fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',25,81,0,0)); os.kill(p.pid,28)
    deadline=time.time()+.5
    while time.time()<deadline:
     ready,_,_=select.select([master],[],[],.05)
     if ready:
      try: out+=os.read(master,4096)
      except OSError: break
    if original!='resize-current': p.terminate()
  except OSError: break
if p.poll() is None: p.terminate()
try: p.wait(timeout=2)
except subprocess.TimeoutExpired: p.kill(); p.wait()
after=termios.tcgetattr(slave); cooked=bool(after[3]&termios.ICANON); print(out.decode(errors='replace')); print('COOKED_STATE='+str(cooked)); print('EXIT='+str(p.returncode)); os.close(master);os.close(slave)
if (p.returncode!=0 and mode not in ('resize-fed',)) or not cooked: sys.exit(1)
