import subprocess
import re
import socket

def check_status_with_os(ip_address):
    """SELF-CLEANING PASSIVE LOOKUP:
    Fires a rapid check packet. If the target machine fails to respond,
    the engine automatically flushes the local Linux kernel's ghost ARP entry
    to ensure the dashboard state drops to Offline instantly.
    """
    try:
        # 1. Fire a fast confirmation ping (1 packet, 0.3 second timeout maximum)
        ping_check = subprocess.run(
            ["ping", "-c", "1", "-W", "1", ip_address], 
            stdout=subprocess.DEVNULL, 
            stderr=subprocess.DEVNULL
        )
        
        # 2. If the machine didn't answer, it's either sleeping or turned off
        if ping_check.returncode != 0:
            # Programmatically flush the ghost ARP entry from the Pi's kernel table
            subprocess.run(["sudo", "ip", "neigh", "flush", "to", ip_address], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return False

        # 3. Double check the system table state to confirm visibility
        output = subprocess.check_output(["arp", "-n", ip_address], text=True)
        if ip_address in output and "incomplete" not in output.lower():
            return True
            
    except:
        pass
    return False

def resolve_ip_to_mac(ip_address):
    """PASSIVE ARP TABLE LOOKUP:
    Scrapes the Pi's internal neighbor table cache matrix.
    """
    try:
        subprocess.run(["ping", "-c", "1", "-W", "1", ip_address], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        output = subprocess.check_output(["arp", "-n", ip_address], text=True)
        match = re.search(r"([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})", output)
        if match:
            return match.group(0).upper()
    except:
        pass
    return None

def send_wol_packet(mac_address):
    """DISPATCH WAKE SIGNAL:
    Broadcasts a rigid 102-byte Magic Packet frame over UDP Port 9.
    """
    try:
        clean_mac = mac_address.replace(":", "").replace("-", "")
        if len(clean_mac) != 12:
            return False
        payload = bytes.fromhex("FFFFFF" * 2 + clean_mac * 16)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            s.sendto(payload, ("255.255.255.255", 9))
        return True
    except:
        return False

def execute_linux_ssh_sleep(ip_address, username):
    ssh_command = ["ssh", "-o", "StrictHostKeyChecking=no", f"{username}@{ip_address}", "sudo systemctl suspend"]
    try:
        subprocess.Popen(ssh_command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except:
        return False
