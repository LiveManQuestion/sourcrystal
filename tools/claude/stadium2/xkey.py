# usage: xkey.py KEY[:ms] ...  (KEY is an X keysym name, e.g. x, z, Return, i)
# "wait:ms" sleeps. Sends to DISPLAY via XTest.
import ctypes, sys, time
x = ctypes.cdll.LoadLibrary('libX11.so.6')
xt = ctypes.cdll.LoadLibrary('libXtst.so.6')
x.XOpenDisplay.restype = ctypes.c_void_p
x.XStringToKeysym.restype = ctypes.c_ulong
x.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
xt.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
x.XFlush.argtypes = [ctypes.c_void_p]
d = x.XOpenDisplay(None)
for arg in sys.argv[1:]:
    name, _, ms = arg.partition(':')
    ms = int(ms or 150)
    if name == 'wait':
        time.sleep(ms / 1000); continue
    kc = x.XKeysymToKeycode(d, x.XStringToKeysym(name.encode()))
    xt.XTestFakeKeyEvent(d, kc, 1, 0); x.XFlush(d); time.sleep(ms / 1000)
    xt.XTestFakeKeyEvent(d, kc, 0, 0); x.XFlush(d); time.sleep(0.25)
