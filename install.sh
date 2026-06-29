#!/bin/bash

# Pi-WoL Sudo Enforcement Layer (Fixed Heredoc Substitutions)
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${COLOR_RED}  [✗] Error: Privileged environment context required.${COLOR_RESET}"
    echo -e "      Please run the installation script using: ${COLOR_BLUE}sudo bash${COLOR_RESET}"
    exit 1
fi

clear

echo -e "${COLOR_BLUE}=========================================${COLOR_RESET}"
echo -e "${COLOR_RED}      ___  _ _ _  _ ____ _    ${COLOR_RESET}"
echo -e "${COLOR_RED}      |__] | | |  | |  | |    ${COLOR_RESET}"
echo -e "${COLOR_RED}      |    | | |__| |__| |___ ${COLOR_RESET}"
echo -e "${COLOR_BLUE}=========================================${COLOR_RESET}"
echo -e "       Pi-WoL Appliance Installer Core   \n"

REAL_USER=${SUDO_USER:-$(whoami)}
REAL_HOME=$(eval echo ~$REAL_USER)

run_with_spinner() {
    local message="$1"
    local command="$2"
    
    eval "$command" > /dev/null 2>&1 &
    local pid=$!
    local spinner=( '/' '-' '\\' '|' )
    
    echo -ne "\033[?25l"
    while kill -0 $pid 2>/dev/null; do
        for icon in "${spinner[@]}"; do
            echo -ne "\r  [${COLOR_BLUE}${icon}${COLOR_RESET}] ${message}..."
            sleep 0.1
        done
    done
    wait $pid
    local return_status=$?
    echo -ne "\033[?25h"
    
    if [ $return_status -eq 0 ]; then
        echo -e "\r  [${COLOR_GREEN}✓${COLOR_RESET}] ${message}"
    else
        echo -e "\r  [${COLOR_RED}✗${COLOR_RESET}] ${message} (Error Code: ${return_status})"
        exit 1
    fi
}

# --- START INSTALLATION FLOW ---

run_with_spinner "Synchronizing Linux core repositories" \
    "apt-get update -y"

run_with_spinner "Installing foundational tooling layers (pip3)" \
    "apt-get install -y python3-pip iproute2"

run_with_spinner "Building destination path nodes (~/Pi-WoL)" \
    "sudo -u $REAL_USER mkdir -p $REAL_HOME/Pi-WoL/core $REAL_HOME/Pi-WoL/templates"

# 🛠️ STREAMING STEP 1: WRITE CORE NETWORK LOGIC DIRECTLY
run_with_spinner "Writing internal network driver engines" "sudo -u $REAL_USER cat << 'EOF' > $REAL_HOME/Pi-WoL/core/network.py
import subprocess
import re
import socket

def check_status_with_os(ip_address):
    try:
        ping_check = subprocess.run([\"ping\", \"-c\", \"1\", \"-W\", \"1\", ip_address], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if ping_check.returncode != 0:
            subprocess.run([\"sudo\", \"ip\", \"neigh\", \"flush\", \"to\", ip_address], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return False
        output = subprocess.check_output([\"arp\", \"-n\", ip_address], text=True)
        if ip_address in output and \"incomplete\" not in output.lower():
            return True
    except:
        pass
    return False

def resolve_ip_to_mac(ip_address):
    try:
        subprocess.run([\"ping\", \"-c\", \"1\", \"-W\", \"1\", ip_address], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        output = subprocess.check_output([\"arp\", \"-n\", ip_address], text=True)
        match = re.search(r\"([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})\", output)
        if match:
            return match.group(0).upper()
    except:
        pass
    return None

def send_wol_packet(mac_address):
    try:
        clean_mac = mac_address.replace(\":\", \"\").replace(\"-\", \"\")
        if len(clean_mac) != 12:
            return False
        payload = bytes.fromhex(\"FFFFFF\" * 2 + clean_mac * 16)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            s.sendto(payload, (\"255.255.255.255\", 9))
        return True
    except:
        return False

def execute_linux_ssh_sleep(ip_address, username):
    ssh_command = [\"ssh\", \"-o\", \"StrictHostKeyChecking=no\", f\"{username}@{ip_address}\", \"sudo systemctl suspend\"]
    try:
        subprocess.Popen(ssh_command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except:
        return False
EOF"

# 🛠️ STREAMING STEP 2: WRITE APPMANAGER APP ENGINE DIRECTLY
run_with_spinner "Writing application main core framework" "sudo -u $REAL_USER cat << 'EOF' > $REAL_HOME/Pi-WoL/app.py
import os
import json
from fastapi import FastAPI, Request, Form, BackgroundTasks
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from core import network

app = FastAPI(title=\"Pi-WoL Core\")
templates = Jinja2Templates(directory=\"templates\")
DB_FILE = \"devices.json\"

SESSION_USER = \"\"
SESSION_PASS = \"\"

def load_devices():
    if not os.path.exists(DB_FILE): return {}
    try:
        with open(DB_FILE, \"r\") as f: return json.load(f)
    except: return {}

def save_devices(devices):
    with open(DB_FILE, \"w\") as f: json.dump(devices, f, indent=4)

@app.get(\"/\")
async def dashboard(request: Request):
    devices = load_devices()
    client_host = request.client.host if request.client else None
    processed_devices = {}
    for alias, info in devices.items():
        if info[\"ip\"] == client_host: continue
        is_online = network.check_status_with_os(info[\"ip\"])
        os_platform = info.get(\"os_type\", \"windows\").lower()
        processed_devices[alias] = {
            \"ip\": info[\"ip\"], \"mac\": info[\"mac\"], \"online\": is_online,
            \"os_type\": os_platform, \"os_label\": \"Windows OS\" if os_platform == \"windows\" else \"Linux (SSH)\"
        }
    return templates.TemplateResponse(request=request, name=\"index.html\", context={
        \"request\": request, \"devices\": processed_devices, \"current_user\": SESSION_USER,
        \"current_pass\": SESSION_PASS, \"session_set\": bool(SESSION_USER and SESSION_PASS)
    })

@app.get(\"/api/lookup/{ip}\")
def fetch_mac_from_cache(ip: str):
    mac_address = network.resolve_ip_to_mac(ip.strip())
    if mac_address: return {\"success\": True, \"mac\": mac_address}
    return {\"success\": False, \"error\": \"Endpoint lookup mismatch.\"}

@app.post(\"/api/add\")
async def web_add_device(alias: str = Form(...), mac: str = Form(...), ip: str = Form(...), os_type: str = Form(...), ssh_user: str = Form(None)):
    devices = load_devices()
    target_alias = alias.lower().strip()
    target_ip = ip.strip()
    target_mac = mac.upper().strip().replace(\"-\", \":\")
    
    for existing_alias, info in devices.items():
        if existing_alias == target_alias: return JSONResponse(status_code=400, content={\"success\": False, \"error\": f\"Profile name '{alias}' is taken.\"})
        if info[\"ip\"] == target_ip: return JSONResponse(status_code=400, content={\"success\": False, \"error\": f\"IP '{target_ip}' already assigned.\"})
        if info[\"mac\"] == target_mac: return JSONResponse(status_code=400, content={\"success\": False, \"error\": f\"MAC '{target_mac}' already registered.\"})

    devices[target_alias] = {\"ip\": target_ip, \"mac\": target_mac, \"os_type\": os_type.lower().strip(), \"ssh_user\": ssh_user.strip() if ssh_user else \"\"}
    save_devices(devices)
    return RedirectResponse(url=\"/\", status_code=303)

@app.post(\"/api/delete/{alias}\")
async def web_delete_device(alias: str):
    devices = load_devices()
    if alias.lower() in devices:
        del devices[alias.lower()]
        save_devices(devices)
    return RedirectResponse(url=\"/\", status_code=303)

@app.post(\"/api/wake/{alias}\")
async def web_wake_device(alias: str, username: str = Form(None), password: str = Form(None), remember: str = Form(None)):
    global SESSION_USER, SESSION_PASS
    devices = load_devices()
    target = alias.lower()
    user = username.strip() if username else SESSION_USER
    text_pass = password if password else SESSION_PASS
    if not user or not text_pass: return RedirectResponse(url=\"/\", status_code=303)
    if remember == \"true\" and username and password:
        SESSION_USER = username.strip()
        SESSION_PASS = password
    if target in devices: network.send_wol_packet(devices[target][\"mac\"])
    return RedirectResponse(url=\"/\", status_code=303)

def execute_winrm_sleep(ip, user, text_pass):
    sleep_payload = '$rundll = \"[DllImport(\\\"powrprof.dll\\\")] public static extern bool SetSuspendState(bool hiber, bool force, bool disable);\"; $type = Add-Type -MemberDefinition $rundll -Name \"Win32Power\" -Namespace \"Win32\" -PassThru; $type::SetSuspendState($false, $false, $false)'
    try:
        import winrm
        session = winrm.Session(ip, auth=(user, text_pass), transport='ntlm', read_timeout_sec=8, operation_timeout_sec=4)
        session.run_ps(sleep_payload)
    except: pass

@app.post(\"/api/sleep/{alias}\")
async def web_sleep_device(alias: str, bg_tasks: BackgroundTasks, username: str = Form(None), password: str = Form(None), remember: str = Form(None)):
    global SESSION_USER, SESSION_PASS
    devices = load_devices()
    target = alias.lower()
    if target not in devices: return RedirectResponse(url=\"/\", status_code=303)
    device_info = devices[target]
    if device_info.get(\"os_type\") == \"linux\":
        bg_tasks.add_task(network.execute_linux_ssh_sleep, device_info[\"ip\"], device_info.get(\"ssh_user\", \"root\"))
        return RedirectResponse(url=\"/\", status_code=303)
    user = username.strip() if username else SESSION_USER
    text_pass = password if password else SESSION_PASS
    if not user or not text_pass: return RedirectResponse(url=\"/\", status_code=303)
    if remember == \"true\" and username and password:
        SESSION_USER = username.strip()
        SESSION_PASS = password
    bg_tasks.add_task(execute_winrm_sleep, device_info[\"ip\"], user, text_pass)
    return RedirectResponse(url=\"/\", status_code=303)
EOF"

# 🛠️ STREAMING STEP 3: WRITE HTML PANEL DASHBOARD DIRECTLY
run_with_spinner "Writing application frontend interface layouts" "sudo -u $REAL_USER cat << 'EOF' > $REAL_HOME/Pi-WoL/templates/index.html
<!DOCTYPE html>
<html lang='en'>
<head>
    <meta charset='UTF-8'>
    <title>Pi-WoL Console</title>
    <link rel='icon' type='image/svg+xml' href='data:image/svg+xml,<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"%23f04444\" stroke-width=\"2\"><path d=\"M18 16a3 3 0 0 0-3-3H9a3 3 0 0 0-3 3M8 2h8v4H8zM12 6v7M6 16h12v4a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2z\"/></svg>'>
    <script src='https://cdn.tailwindcss.com'></script>
    <link rel='stylesheet' href='https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css'>
    <style>
        body { background-color: #0f1216; }
        .pi-panel { background-color: #161a1f; border-color: #222933; }
        .pi-dark { background-color: #0b0d10; border-color: #1c222a; }
        .pi-border { border-color: #222933; }
        .pi-text-muted { color: #8a99ad; }
        .pi-btn-blue { background-color: #2463eb; }
        .pi-btn-emerald { background-color: #107c41; }
    </style>
</head>
<body class='text-slate-200 min-h-screen font-sans antialiased text-sm'>
    <div class='h-1 w-full bg-gradient-to-r from-red-500 to-blue-600'></div>
    <div class='max-w-7xl mx-auto px-4 py-8'>
        <div class='grid grid-cols-1 lg:grid-cols-12 gap-8'>
            <div class='lg:col-span-5 space-y-6'>
                <div class='pi-panel border rounded-2xl p-6 shadow-xl flex items-center gap-4'>
                    <div class='border-2 border-[#f04444] text-[#f04444] p-3 rounded-xl shadow-md'>
                        <svg class='w-6 h-6' fill='none' stroke='currentColor' stroke-width='2' viewBox='0 0 24 24'><path d='M18 16a3 3 0 0 0-3-3H9a3 3 0 0 0-3 3M8 2h8v4H8zM12 6v7M6 16h12v4a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2z'/></svg>
                    </div>
                    <div>
                        <h1 class='text-xl font-black text-white leading-none'>Pi-WoL</h1>
                        <p class='text-[11px] font-bold tracking-widest uppercase pi-text-muted mt-1.5'>Network Core Console</p>
                    </div>
                </div>
                <div class='pi-panel border rounded-2xl p-6 shadow-xl space-y-5'>
                    <form id='nodeRegistrationForm' onsubmit='validateNodeForm(event);' class='space-y-4 m-0' novalidate>
                        <div>
                            <label class='block text-[11px] font-black uppercase tracking-wider pi-text-muted mb-1.5'>Custom Alias Handle</label>
                            <input type='text' id='form_alias_field' class='w-full pi-dark border rounded-xl px-3.5 py-2.5 text-white focus:outline-none'>
                        </div>
                        <div class='grid grid-cols-2 gap-4'>
                            <div>
                                <label class='block text-[11px] font-black uppercase tracking-wider pi-text-muted mb-1.5'>Platform OS</label>
                                <select id='form_os_select' class='w-full pi-dark border rounded-xl px-3.5 py-2.5 text-white focus:outline-none'>
                                    <option value='windows' selected>Windows OS</option>
                                    <option value='linux'>Linux OS</option>
                                </select>
                            </div>
                            <div>
                                <label class='block text-[11px] font-black uppercase tracking-wider pi-text-muted mb-1.5'>SSH User</label>
                                <input type='text' id='modal_ssh_user' placeholder='e.g. root' class='w-full pi-dark border rounded-xl px-3.5 py-2.5 text-white focus:outline-none'>
                            </div>
                        </div>
                        <div>
                            <div class='flex justify-between mb-1.5'><label class='text-[11px] font-black uppercase pi-text-muted'>Static IP</label><button type='button' onclick='triggerAutoMacLookup()' class='text-blue-400 text-[10px] uppercase font-bold'>Auto-Detect MAC</button></div>
                            <input type='text' id='form_ip_field' class='w-full pi-dark border rounded-xl px-3.5 py-2.5 text-white focus:outline-none'>
                        </div>
                        <div>
                            <label class='block text-[11px] font-black uppercase tracking-wider pi-text-muted mb-1.5'>MAC Address</label>
                            <input type='text' id='form_mac_field' class='w-full pi-dark border rounded-xl px-3.5 py-2.5 text-white focus:outline-none'>
                            <span id='lookupStatusLabel' class='text-[10px] block mt-1.5'></span>
                        </div>
                        <button type='submit' class='w-full pi-btn-blue text-white font-bold py-3 rounded-xl uppercase text-xs tracking-wider shadow-lg'>Commit Device to Disk</button>
                    </form>
                </div>
            </div>
            <div class='lg:col-span-7'>
                <div class='pi-panel border rounded-2xl p-6 shadow-xl min-h-[510px]'>
                    <div class='flex justify-between items-center mb-6 border-b pi-border pb-4'><h2 class='text-xs font-black uppercase pi-text-muted'>Environment Inventory</h2><button onclick='window.location.reload();' class='text-blue-400 font-bold text-[10px] uppercase'>Sync States</button></div>
                    <div class='grid grid-cols-1 md:grid-cols-2 gap-6'>
                        {% if not devices %}
                        <div class='col-span-full py-24 text-center'><h3 class='text-white font-black'>No Node Records Registered</h3></div>
                        {% else %}
                            {% for alias, info in devices.items() %}
                            <div class='pi-dark border rounded-2xl p-5 shadow-lg flex flex-col justify-between' data-alias='{{ alias }}'>
                                <div>
                                    <div class='flex justify-between items-start mb-4'>
                                        <div>
                                            <h3 class='text-base font-black text-white capitalize font-mono'>{{ alias }}</h3>
                                            <div class='flex items-center gap-2 mt-2'>
                                                {% if info.online %}
                                                    <span class='h-2.5 w-2.5 rounded-full bg-emerald-500 shadow-md'></span><span class='text-[11px] font-black uppercase text-emerald-400'>Online ({{ info.os_label }})</span>
                                                {% else %}
                                                    <span class='h-2.5 w-2.5 rounded-full bg-red-500'></span><span class='text-[11px] font-black uppercase text-red-500'>Offline Profile</span>
                                                {% endif %}
                                            </div>
                                        </div>
                                        <form action='/api/delete/{{ alias }}' method='post' onsubmit='return confirm(\"Purge workflow profile?\");'><button type='submit' class='text-slate-600 hover:text-red-500'><i class='fa-solid fa-trash-can'></i></button></form>
                                    </div>
                                    <div class='space-y-2.5 pi-panel p-4 rounded-xl border mb-5 text-xs font-mono shadow-inner'><div class='flex justify-between'><span>IP Target</span><span class='text-slate-200 font-bold'>{{ info.ip }}</span></div><div class='flex justify-between border-t border-slate-800/40 pt-2'><span>MAC Layer</span><span class='text-slate-400'>{{ info.mac }}</span></div></div>
                                </div>
                                <div>
                                    {% if info.online %}
                                        <button type='button' onclick='interceptSleepTrigger(\"{{ alias }}\", \"{{ info.os_type }}\")' class='w-full bg-blue-600/10 hover:bg-blue-600 text-blue-400 hover:text-white border border-blue-500/20 font-bold py-3 rounded-xl text-xs uppercase transition shadow-md'><i class='fa-solid fa-moon mr-1'></i> Standby Sleep Trigger</button>
                                    {% else %}
                                        <button type='button' onclick='interceptWakeTrigger(\"{{ alias }}\")' class='w-full pi-btn-emerald text-white font-extrabold py-3 rounded-xl text-xs uppercase shadow-lg'><i class='fa-solid fa-power-off mr-1'></i> Dispatch Wake Signal</button>
                                    {% endif %}
                                </div>
                            </div>
                            {% endfor %}
                        {% endif %}
                    </div>
                </div>
            </div>
        </div>
    </div>
    <div id='authModal' class='hidden fixed inset-0 bg-slate-950/80 backdrop-blur-md flex items-center justify-center p-4 z-50'>
        <div class='pi-panel border rounded-2xl max-w-md w-full p-6 relative shadow-2xl'>
            <button onclick='document.getElementById(\"authModal\").classList.add(\"hidden\")' class='absolute top-4 right-4 text-slate-500'><i class='fa-solid fa-xmark'></i></button>
            <div class='flex items-center gap-3 mb-4'><h3 id='authModalTitle' class='text-lg font-black text-white'>Authentication Required</h3></div>
            <p id='authModalDesc' class='text-xs pi-text-muted mb-5'>Provide console admin security credentials.</p>
            <form id='authModalForm' method='post' class='space-y-4 m-0'>
                <div class='grid grid-cols-2 gap-4'>
                    <div><label class='block text-[10px] font-black uppercase pi-text-muted mb-1.5'>Console User</label><input type='text' name='username' class='w-full pi-dark border rounded-xl px-3 py-2.5 text-sm font-mono text-white focus:outline-none' required></div>
                    <div><label class='block text-[10px] font-black uppercase pi-text-muted mb-1.5'>Console Password</label><input type='password' name='password' class='w-full pi-dark border rounded-xl px-3 py-2.5 text-sm font-mono text-white focus:outline-none' required></div>
                </div>
                <div class='pi-dark border rounded-xl p-4'><label class='flex items-start gap-3 cursor-pointer text-xs'><input type='checkbox' name='remember' value='true' class='mt-1'><span>Remember credentials for session</span></label></div>
                <button type='submit' class='w-full pi-btn-blue text-white font-bold py-3.5 rounded-xl uppercase text-xs shadow-lg'>Authorize Execution</button>
            </form>
        </div>
    </div>
    <script>
        const SESSION_ACTIVE = {{ 'true' if session_set else 'false' }};
        async function validateNodeForm(event) {
            event.preventDefault();
            const aliasI = document.getElementById('form_alias_field'); const ipI = document.getElementById('form_ip_field'); const macI = document.getElementById('form_mac_field');
            const osS = document.getElementById('form_os_select'); const sshI = document.getElementById('modal_ssh_user'); const lbl = document.getElementById('lookupStatusLabel');
            const alias = aliasI.value.trim(); const ip = ipI.value.trim(); const mac = macI.value.trim();
            if(!alias || !/^(\d{1,3}\.){3}\d{1,3}$/.test(ip) || !/^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/.test(mac)) {
                lbl.className = \"text-[10px] text-rose-400 font-bold block mt-1.5\"; lbl.innerHTML = \"Validation Failed: Check parameters structure inputs.\"; return;
            }
            lbl.className = \"text-[10px] text-blue-400 block mt-1.5 font-medium\"; lbl.innerHTML = \"Verifying parameters entries...\";
            const fd = new FormData(); fd.append('alias', alias); fd.append('ip', ip); fd.append('mac', mac); fd.append('os_type', osS.value); fd.append('ssh_user', sshI.value);
            try {
                const res = await fetch('/api/add', { method: 'POST', body: fd });
                if (res.ok) { lbl.className = \"text-[10px] text-emerald-400 font-bold block mt-1.5\"; lbl.innerHTML = \"Node committed successfully!\"; setTimeout(() => { window.location.reload(); }, 800); }
                else { const data = await res.json(); lbl.className = \"text-[10px] text-rose-400 font-bold block mt-1.5\"; lbl.innerHTML = \"Conflict: \" + data.error; }
            } catch { lbl.className = \"text-[10px] text-rose-500 block mt-1.5\"; lbl.innerHTML = \"Error routing engine data fields.\"; }
        }
        async function triggerAutoMacLookup() {
            const ipVal = document.getElementById('form_ip_field').value.trim(); const macInput = document.getElementById('form_mac_field'); const label = document.getElementById('lookupStatusLabel');
            if (!ipVal) { label.className = \"text-[10px] text-rose-400 font-bold block mt-1.5\"; label.innerHTML = \"Provide an IP address first.\"; return; }
            label.className = \"text-[10px] text-amber-400 font-medium block mt-1.5 animate-pulse\"; label.innerHTML = \"Refreshing routing cache...\";
            try {
                const res = await fetch('/api/lookup/' + ipVal); const data = await res.json();
                if (data.success) { macInput.value = data.mac; label.className = \"text-[10px] text-emerald-400 font-bold block mt-1.5\"; label.innerHTML = \"Target resolved and mapped!\"; }
                else { label.className = \"text-[10px] text-rose-400 block mt-1.5\"; label.innerHTML = \"Passive lookup failed.\"; }
            } catch { label.className = \"text-[10px] text-rose-500 block mt-1.5\"; label.innerHTML = \"Lookup backend endpoint error.\"; }
        }
        function interceptWakeTrigger(alias) {
            if (SESSION_ACTIVE) { const f = document.createElement('form'); f.method = 'POST'; f.action = '/api/wake/' + alias; document.body.appendChild(f); f.submit(); }
            else { document.getElementById('authModalTitle').innerText = \"Wake Authorization Required\"; document.getElementById('authModalForm').action = '/api/wake/' + alias; document.getElementById('authModal').classList.remove('hidden'); }
        }
        function interceptSleepTrigger(alias, os_type) {
            if (os_type === 'linux' || SESSION_ACTIVE) { const f = document.createElement('form'); f.method = 'POST'; f.action = '/api/sleep/' + alias; document.body.appendChild(f); f.submit(); }
            else { document.getElementById('authModalTitle').innerText = \"Sleep Action Authentication\"; document.getElementById('authModalForm').action = '/api/sleep/' + alias; document.getElementById('authModal').classList.remove('hidden'); }
        }
    </script>
</body>
</html>
EOF"

run_with_spinner "Deploying runtime application dependencies (fastapi, uvicorn, winrm)" \
    "pip3 install fastapi uvicorn pywinrm --break-system-packages"

run_with_spinner "Initializing database local layout storage profiles" \
    "cd $REAL_HOME/Pi-WoL && echo '{}' > devices.json"

run_with_spinner "Injecting system administrative permission configurations" \
    "SUDOERS_RULE=\"$REAL_USER ALL=(ALL) NOPASSWD: /usr/sbin/ip neigh flush *\" && if ! sudo grep -qF \"\$SUDOERS_RULE\" /etc/sudoers; then echo \"\$SUDOERS_RULE\" | sudo tee -a /etc/sudoers; fi"

run_with_spinner "Attaching and launching system daemon background wrapper engine" \
    "sudo tee /etc/systemd/system/piwol.service > /dev/null <<EOF
[Unit]
Description=Pi-WoL Network Appliance
After=network.target

[Service]
User=$REAL_USER
WorkingDirectory=$REAL_HOME/Pi-WoL
ExecStart=/usr/local/bin/uvicorn app:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable piwol.service && systemctl restart piwol.service"

# --- SUCCESS DISPLAY LAYOUT ---
PI_IP=$(hostname -I | awk '{print $1}')
echo -e "\n${COLOR_GREEN}=====================================================${COLOR_RESET}"
echo -e " 🎉 ${COLOR_GREEN}Pi-WoL Installed Successfully Under Sudo Contexts!${COLOR_RESET}"
echo -e " 🌐 Access your dashboard console appliance via:"
echo -e "    ${COLOR_BLUE}http://${PI_IP}:8000${COLOR_RESET}"
echo -e "${COLOR_GREEN}=====================================================${COLOR_RESET}"