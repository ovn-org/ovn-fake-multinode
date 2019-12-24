#!/usr/bin/python3

import sys
import ipaddress

try:
    cidr = sys.argv[1]
    start_addr = sys.argv[2]
    index = int(sys.argv[3])

    ip_list = [str(ip) for ip in ipaddress.IPv4Network(cidr)]
    saddr_index = ip_list.index(start_addr)
    if len(ip_list) > saddr_index + index:
        print(ip_list[saddr_index + index])
except:
    sys.exit(1)

sys.exit(0)
