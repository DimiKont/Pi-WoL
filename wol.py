import sys
import json
import os
from core import network

DB_FILE = "devices.json"

def load_devices():
    """Loads the device list from JSON file, initializing a new one if missing."""
    if not os.path.exists(DB_FILE):
        with open(DB_FILE, "w") as f:
            json.dump({}, f, indent=4)
        return {}
    try:
        with open(DB_FILE, "r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        print("[!] Error: devices.json is corrupted.")
        return {}

def save_devices(devices):
    """Saves the current device map back to the JSON store."""
    with open(DB_FILE, "w") as f:
        json.dump(devices, f, indent=4)

def print_usage():
    print("\n⚡ Smart WoL Terminal Tool CLI")
    print("-" * 50)
    print("Usage:")
    print("  python wol.py list                 - Show all saved devices & live online status")
    print("  python wol.py scan                 - Automagically scan the network for open devices")
    print("  python wol.py wake [alias]         - Broadcast a magic packet to boot a device")
    print("  python wol.py add [alias] [mac] [ip]- Manually save a device to inventory\n")

def main():
    if len(sys.argv) < 2:
        print_usage()
        sys.exit(1)

    action = sys.argv[1].lower()
    devices = load_devices()

    # COMMAND: list
    if action == "list":
        if not devices:
            print("[*] Your inventory is empty. Try running: python wol.py scan")
            sys.exit(0)
            
        print(f"\n{'Alias':<15} {'Device Name/IP':<15} {'MAC Address':<20} {'Status':<10}")
        print("-" * 65)
        for alias, info in devices.items():
            online = network.check_status(info["ip"])
            status_str = "🟢 ONLINE" if online else "🔴 OFFLINE"
            print(f"{alias:<15} {info['ip']:<15} {info['mac']:<20} {status_str:<10}")
        print()

    # COMMAND: scan
    elif action == "scan":
        print("[*] Querying network tables for active devices...")
        found = network.discover_devices()
        
        if not found:
            print("[-] No active open devices found. Wake target manually or check connection.")
            sys.exit(0)
            
        print(f"\n{'IP Address':<15} {'MAC Address':<20}")
        print("-" * 35)
        for dev in found:
            print(f"{dev['ip']:<15} {dev['mac']:<20}")
        print(f"\n[+] Found {len(found)} responsive devices on your network segment.")
        print("[*] To track one, run: python wol.py add [alias] [mac] [ip]")

    # COMMAND: wake
    elif action == "wake":
        if len(sys.argv) < 3:
            print("[!] Error: Missing target device alias.")
            sys.exit(1)
            
        alias = sys.argv[2].lower()
        if alias in devices:
            device = devices[alias]
            print(f"[*] Sending magic wake-on-lan sequence to {alias.upper()} ({device['mac']})...")
            if network.send_wol_packet(device["mac"]):
                print("[+] Packet broadcast complete. Checking power state...")
            else:
                print("[-] Broadcast failure. Verify network interface permissions.")
        else:
            print(f"[!] Error: Alias '{alias}' doesn't match any saved devices.")

    # COMMAND: add
    elif action == "add":
        if len(sys.argv) < 5:
            print("[!] Error: Syntax is 'python wol.py add [alias] [mac] [ip]'")
            sys.exit(1)
            
        alias = sys.argv[2].lower()
        mac = sys.argv[3].upper()
        ip = sys.argv[4]
        
        devices[alias] = {"ip": ip, "mac": mac}
        save_devices(devices)
        print(f"[+] Successfully saved tracking identity for '{alias}'!")

    else:
        print_usage()

if __name__ == "__main__":
    main()