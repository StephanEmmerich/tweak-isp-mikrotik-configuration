# RouterOS 6.48.2
# software id = C2GA-BNAT
#
# model = RB760iGS

# Two bridges. VLAN34 bridge such that is uses the same as 'WAN MAC Address' in Zyxel router
/interface bridge
add admin-mac={LAN_INFORMATION_MAC-ADDRESS} arp=proxy-arp auto-mac=no comment="Lokaal netwerk" igmp-snooping=yes name=bridge_local protocol-mode=none
add admin-mac={WAN_INFORMATION_MAC-ADDRESS} auto-mac=no name=bridge_vlan34_wan

#Internet is on Ether1 (not sfp1)
/interface ethernet
set [ find default-name=ether1 ] arp=proxy-arp l2mtu=1598 loop-protect=off
set [ find default-name=sfp1 ] disabled=yes

#tv=vlan1.4, internet=vlan1.34 (eth1, vlanX=.XX)
/interface vlan
add interface=ether1 name=vlan1.4 vlan-id=4
add interface=bridge_vlan34_wan loop-protect=off name=vlan1.34 vlan-id=34

/interface wireless security-profiles set [ find default=yes ] supplicant-identity=MikroTik

#necessary to get gateway information and routes. 0xXXXXXXXXXX is IPTV MAC Address (second paragraph), without colons (no ':')
/ip dhcp-client option add code=121 name=classless-static-route-option value=0x{TWICE_IPTV_MAC_WITHOUT_COLONS}

/ip pool add name=thuis ranges=192.168.88.1-192.168.88.100

/ip dhcp-server add address-pool=thuis disabled=no interface=bridge_local name=dhcp_local_lan

/routing bgp instance set default disabled=yes

# Setup internet bridge, using vlan34 interface (over ether1)
/interface bridge port
add bridge=bridge_vlan34_wan interface=ether1
add bridge=bridge_local comment="Bridge LAN Internet" interface=ether2
add bridge=bridge_local comment="Bridge LAN Internet" interface=ether3
add bridge=bridge_local comment="Bridge LAN Internet" interface=ether4
add bridge=bridge_local comment="Bridge LAN Internet" interface=ether5

/interface detect-internet set detect-interface-list=all wan-interface-list=dynamic

# Set IP router and internal route
/ip address add address=192.168.88.254/24 comment="Router IP address" interface=bridge_local network=192.168.88.0

# Get WAN information from Tweak.
# Second line (IPTV) is important. Do DHCP request with option 121. It returns gateway information and set 'IP routes', but with distance 255. Careful, if route-distance is 1, then you could have no internet as all traffic goes over the 10.x range.
/ip dhcp-client 
add comment="DHCP WAN Tweak" disabled=no interface=vlan1.34
add add-default-route=special-classless comment="DHCP IPTV Tweak" default-route-distance=255 dhcp-options=hostname,clientid,classless-static-route-option disabled=no interface=vlan1.4 use-peer-ntp=no

# Devices connected on router. Statically set TV box.
/ip dhcp-server lease
add address=192.168.88.7 comment="Linksys PAP2T" mac-address={MAC_OF_LINKSYS_PAP2T} server=dhcp_local_lan
add address=192.168.88.1 comment="Deco X60 1" mac-address={MAC_OF_DECO_X60_MAIN_SATTELITE} server=dhcp_local_lan
add address=192.168.88.2 comment="Deco X60 2" mac-address={MAC_OF_DECO_X60_SECOND_SATTELITE} server=dhcp_local_lan
add address=192.168.88.8 comment="Amino TV Box" mac-address={MAC_ADDRESS_OF_AMINO_BOX} server=dhcp_local_lan

# Internal DHCP LAN
/ip dhcp-server network add address=192.168.88.0/24 dns-server=192.168.88.254 domain=thuis.local gateway=192.168.88.254 netmask=24

# Also use Google DNS, they are faster. Remote requests necessary, else internally no DNS traffic. Set DNS firewall filter!
/ip dns set allow-remote-requests=yes cache-max-ttl=1d servers=8.8.8.8,8.8.4.4

# IP addresses that should be rejected. Is crap traffic.
/ip firewall address-list
add address=0.0.0.0/8 comment="Self-Identification [RFC 3330]" list=Unrouted
add address=10.0.0.0/8 comment="Private class A" list=Unrouted
add address=127.0.0.0/8 comment="Loopback [RFC 3330]" list=Unrouted
add address=169.254.0.0/16 comment="Link Local [RFC 3330]" list=Unrouted
add address=172.16.0.0/12 comment="Private class B" list=Unrouted
add address=192.0.2.0/24 comment="Reserved - IANA - TestNet1" list=Unrouted
add address=192.88.99.0/24 comment="6to4 Relay Anycast [RFC 3068]" list=Unrouted
add address=198.18.0.0/15 comment="NIDB Testing" list=Unrouted
add address=198.51.100.0/24 comment="Reserved - IANA - TestNet2" list=Unrouted
add address=203.0.113.0/24 comment="Reserved - IANA - TestNet3" list=Unrouted
add address=192.168.0.0/16 comment="Private class C" list=Unrouted

# Important rules
# - Fast track to speed up stuff. The vlan1.34 of them can most likely be removed.
# - Protect yourself from external DNS calls. You should not become a DNS server (e.g. amplification attacks)
# - IPTV requires to multicast stuff around (on vlan 1.4) allow it (just to be sure)
/ip firewall filter
add action=accept chain=forward comment="Accept only established and related" connection-state=established,related
add action=fasttrack-connection chain=forward comment="Fast forward connections" connection-state=established,related
add action=accept chain=input comment="Forward established en related WAN" connection-state=established,related in-interface=vlan1.34
add action=accept chain=forward comment="Accept DST traffic" connection-nat-state=dstnat in-interface=vlan1.34
add action=drop chain=forward comment="Drop invalid WAN connections" connection-state=invalid in-interface=vlan1.34
add action=drop chain=input comment="Protect from external DNS calls" dst-port=53 in-interface=vlan1.34 protocol=udp
add action=reject chain=input comment="Protect from external DNS calls" dst-port=53 in-interface=vlan1.34 protocol=tcp reject-with=icmp-host-unreachable
add action=reject chain=input comment="Reject icmp traffic" in-interface=vlan1.34 protocol=tcp reject-with=icmp-port-unreachable
add action=reject chain=input in-interface=vlan1.34 reject-with=icmp-network-unreachable
add action=reject chain=input in-interface=vlan1.34 reject-with=icmp-network-unreachable
add action=drop chain=input dst-address={YOUR_PUBLIC_IP} protocol=icmp
add action=drop chain=forward comment="Drop unrouted addresses" in-interface=vlan1.34 src-address-list=Unrouted
add action=drop chain=forward comment="Drop all from WAN not DSTNATed" connection-nat-state=!dstnat connection-state=new in-interface=vlan1.34
add action=accept chain=input comment="IPTV multicast" dst-address=224.0.0.0/8 in-interface=vlan1.4
add action=accept chain=forward in-interface=vlan1.4 protocol=udp
add action=accept chain=forward comment="IPTV multicast" dst-address=224.0.0.0/8 in-interface=vlan1.4

# Port forwarding and masquerading
# Masquerading must be added, else nothing will work. The rules could perhaps be one, be this is more explicit (and safe)
# The 
/ip firewall nat
add action=masquerade chain=srcnat comment="Masquerade internet traffic" src-address=192.168.88.0/24
add action=dst-nat chain=dstnat comment="All dst-nat on VLAN4 to TV box to ensure clean streaming since there is no RTSP protocol on Mikrotik" dst-address=!224.0.0.0/8 in-interface=vlan1.4 to-addresses=192.168.88.8
add action=dst-nat chain=dstnat comment="Example FTP forward" dst-port=21 protocol=tcp to-addresses=192.168.88.1 to-ports=21
add action=dst-nat chain=dstnat comment="Example FTP PASV forward" dst-port=3500 dst-address={YOUR_PUBLIC_IP} protocol=tcp to-addresses=192.168.88.1 to-ports=3500

# For security shutdown everything
/ip firewall service-port
set ftp disabled=yes
set tftp disabled=yes
set irc disabled=yes
set h323 disabled=yes
set sip disabled=yes
set pptp disabled=yes
set udplite disabled=yes
set dccp disabled=yes
set sctp disabled=yes

# This is important, if you don't set this. Pause TV (and streams) don't work properly. The 'distance=1' is important.
# Also note the gateway, this is my gateway provided from DHCP on VLAN1.4. I can change though.
# After executing this configuration. Login into the RouterBoard and check 'IP -> Routes'. Ensure all the routes are available. If they are not available, change the IP gateway to the address given from DHCP, they are there too but with distance=255.
/ip route
add comment=TV_static_route1 distance=1 dst-address=185.24.175.0/24 gateway=10.10.32.1
add comment=TV_static_route2 distance=1 dst-address=185.41.48.0/24 gateway=10.10.32.1

# For security, manage Mikrotik RouterBoard with Winbox only. Winbox is shielded off WAN so secure.
/ip service
set telnet disabled=yes
set ftp disabled=yes
set www disabled=yes
set ssh disabled=yes
set api disabled=yes
set api-ssl disabled=yes

# UPNP stuff, some people hate, some people like it.
`/ip upnp set show-dummy-rule=no

/ip upnp interfaces add interface=bridge_local type=internal`

# Install multicast package first:
# 1. Download all-packages-{architecture} from https://mikrotik.com/download
# 2. Extract and copy the multicast package into Winbox file screen
# 3. Reboot router and package should be installed
/routing igmp-proxy set quick-leave=yes
/routing igmp-proxy interface
add alternative-subnets=0.0.0.0/0 interface=vlan1.4 upstream=yes
add
add interface=bridge_local

# Some default stuff
/system clock set time-zone-name=Europe/Amsterdam

# More secure to use own username and password and limit access from specific IP
/user add name={MY USERNAME} password={PASSWORD} group=full
/user remove admin
/user set {MY USERNAME} allowed-address=192.168.88.0/24
