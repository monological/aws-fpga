#!python3

import sys
import re
import subprocess
import random

vcmd_i = 0

def random_int(b):
    w = 0
    for i in range(b):
        w |= random.randint(0, 1) << i
    return w

def bits(w, b, s):
    return (w >> s) & ((1 << b)-1)

def vcmd(cmd, addr, b):
    global vcmd_i
    w = 0
    vcmd_i += 1
    vcmd_i = vcmd_i % 2
    cmd = 0 if cmd == 'r' else 1
    addr = addr & 0x3f
    b = b & 0xff

    w |= cmd << 0
    w |= vcmd_i << 1
    w |= addr << 2
    w |= b << 8

    print ('{:016b}'.format(w))

    o = subprocess.check_output('sudo fpga-set-virtual-dip-switch -S 0 -D {:016b}'.format(w), shell=True)
    o = subprocess.check_output('sudo fpga-get-virtual-led -S 0', shell=True)
    o = o.decode("utf-8")
    m = re.search('[01]+-[01]+-[01]+-[01]+', o)
    b = 0
    s = m.group(0)
    for i in range(8):
        if s[-1] == '-':
            s = s[:-1]
        if s[-1] == '1':
            b |= 1 << i
        s = s[:-1]
    print ('{:08b}'.format(b))
    # print ('{}: {:08b}'.format(o, b))
    return b





def set_dma_addr(addr):
    for i in range(8):
        b = bits(addr, 8, 8*i)
        vcmd('w', 0+i, b)

def get_dma_addr():
    a = 0
    for i in range(8):
        b = vcmd('r', 0+i, 0)
        a |= b << (i*8)
    return a

def set_dma_data(data):
    for i in range(8):
        b = bits(data, 8, 8*i)
        vcmd('w', 8+i, b)

def get_dma_data():
    a = 0
    for i in range(8):
        b = vcmd('r', 8+i, 0)
        a |= b << (i*8)
    return a


vcmd('r', 0, 0x00)

dma_addr = int(sys.argv[1], 16)
dma_data = int(sys.argv[2], 16)

set_dma_addr(dma_addr)
set_dma_data(dma_data)

print ('{:x}'.format(get_dma_addr()))

# dma_go
vcmd('w', 0x3f, 0xff)
