import os,pty,subprocess,sys,termios,select,time,fcntl,struct
mode=sys.argv[1]; artifact=sys.argv[2]; master,slave=pty.openpty(); fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',24,80,0,0)); before=termios.tcgetattr(slave); p=subprocess.Popen(['/opt/elm-harness/current/runtime/node','tests/pty/terminal-child.cjs',mode,artifact],stdin=slave,stdout=slave,stderr=slave,close_fds=True); out=b''; end=time.time()+5
while time.time()<end and p.poll() is None:
 r,_,_=select.select([master],[],[],.1)
 if r:
  try: out+=os.read(master,4096)
  except OSError: break
p.wait(timeout=2); after=termios.tcgetattr(slave); cooked=bool(after[3]&termios.ICANON); print(out.decode(errors='replace')); print('COOKED_STATE='+str(cooked)); print('EXIT='+str(p.returncode)); os.close(master);os.close(slave)
if p.returncode!=0 or not cooked: sys.exit(1)
