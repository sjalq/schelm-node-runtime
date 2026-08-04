import os,pty,subprocess,sys,termios,select,time,fcntl,struct
mode=sys.argv[1]; artifact=sys.argv[2]; master,slave=pty.openpty(); fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',24,80,0,0)); before=termios.tcgetattr(slave); p=subprocess.Popen(['/opt/elm-harness/current/runtime/node','tests/pty/terminal-child.cjs',mode,artifact],stdin=slave,stdout=slave,stderr=slave,close_fds=True); out=b''; end=time.time()+5
if mode=='input-replay':
 time.sleep(.5); os.write(master,b'\xff'); time.sleep(.1); os.write(master,b'\x04'); time.sleep(.1); os.write(master,b'\x04')
if mode=='fanout-resize':
 time.sleep(.5); fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',25,81,0,0)); os.kill(p.pid,28)
while time.time()<end and p.poll() is None:
 r,_,_=select.select([master],[],[],.1)
 if r:
  try: out+=os.read(master,4096)
  except OSError: break
p.wait(timeout=2); after=termios.tcgetattr(slave); cooked=bool(after[3]&termios.ICANON); print(out.decode(errors='replace')); print('COOKED_STATE='+str(cooked)); print('EXIT='+str(p.returncode)); os.close(master);os.close(slave)
if p.returncode!=0 or not cooked: sys.exit(1)
