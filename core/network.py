import os
import socket
import struct
import subprocess

def send_wol_packet(mac_address: str) -> bool:
    """Sends a WoL magic packet to the specified MAC address."""
    try:
        # Standardize formatting by removing colons and hyphens
        clean_mac = mac_address.replace(":", "").replace("-", "")
        if len(clean_mac) != 12:
            return False
        
        # Pack the hexadecimal MAC string into raw binary bytes
        mac_bytes = struct.pack('!6B', *[int(clean_mac[i:i+2], 16) for i in range(0, 12, 2)])
        
        # Payload: 6 bytes of 0xFF followed by the MAC address repeated 16 times
        magic_packet = b'\xff' * 6 + mac_bytes * 16
        
        # Broadcast over UDP socket via Port 9
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            sock.sendto(magic_packet, ('255.255.255.255', 9))
        return True
    except Exception:
        return False

def check_status(ip_address: str) -> bool:
    """Returns True if the target device responds to a ping sweep request."""
    try:
        # -c 1 (1 packet), -W 1 (1 second timeout duration)
        result = subprocess.run(
            ["ping", "-c", "1", "-W", "1", ip_address],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        return result.returncode == 0
    except Exception:
        return False

def discover_devices() -> list:
    """Scans the local network cache to find open/active devices."""
    discovered = []
    
    # On Linux/Raspberry Pi, active network neighbors are tracked in /proc/net/arp
    if os.path.exists("/proc/net/arp"):
        with open("/proc/net/arp", "r") as f:
            lines = f.readlines()[1:]  # Skip the column header line
            for line in lines:
                parts = line.split()
                if len(parts) >= 4:
                    ip = parts[0]
                    mac = parts[3]
                    # Filter out empty entries or incomplete handshakes
                    if mac != "00:00:00:00:00:00" and len(mac) == 17:
                        discovered.append({"ip": ip, "mac": mac.upper()})
    return discovered