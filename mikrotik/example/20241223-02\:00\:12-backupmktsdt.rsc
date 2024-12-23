# dec/23/2024 02:00:08 by RouterOS 6.49.1
# software id = XXXX-XXXX
#
# model = RB1100x4
# serial number = XXXXXXXXXXXX
/interface ethernet
set [ find default-name=ether1 ] name=ether1-Lan
set [ find default-name=ether2 ] name=ether2-Wan
set [ find default-name=ether10 ] name=ether10-Mng
/interface ethernet switch port
set 0 default-vlan-id=0
set 1 default-vlan-id=0
set 2 default-vlan-id=0
set 3 default-vlan-id=0
set 4 default-vlan-id=0
set 5 default-vlan-id=0
set 6 default-vlan-id=0
set 7 default-vlan-id=0
set 8 default-vlan-id=0
set 9 default-vlan-id=0
set 10 default-vlan-id=0
set 11 default-vlan-id=0
set 12 default-vlan-id=0
set 13 default-vlan-id=0
set 14 default-vlan-id=0
set 15 default-vlan-id=0
/interface list
add exclude=dynamic name=discover
/interface wireless security-profiles
set [ find default=yes ] supplicant-identity=RouterOS
..........
