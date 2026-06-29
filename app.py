import os
import json
from fastapi import FastAPI, Request, Form, BackgroundTasks
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from core import network

app = FastAPI(title="Smart-WoL Absolute Core Engine")
templates = Jinja2Templates(directory="templates")
DB_FILE = "devices.json"

SESSION_USER = ""
SESSION_PASS = ""

def load_devices():
    if not os.path.exists(DB_FILE):
        return {}
    try:
        with open(DB_FILE, "r") as f:
            return json.load(f)
    except:
        return {}

def save_devices(devices):
    with open(DB_FILE, "w") as f:
        json.dump(devices, f, indent=4)

@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    devices = load_devices()
    client_host = request.client.host if request.client else None
    
    processed_devices = {}
    for alias, info in devices.items():
        if info["ip"] == client_host:
            continue
            
        is_online = network.check_status_with_os(info["ip"])
        os_platform = info.get("os_type", "windows").lower()
        
        processed_devices[alias] = {
            "ip": info["ip"],
            "mac": info["mac"],
            "online": is_online,
            "os_type": os_platform,
            "os_label": "Windows OS" if os_platform == "windows" else "Linux (SSH)"
        }
        
    render_context = {
        "request": request,
        "devices": processed_devices,
        "current_user": SESSION_USER,
        "current_pass": SESSION_PASS,
        "session_set": bool(SESSION_USER and SESSION_PASS)
    }
    return templates.TemplateResponse(request=request, name="index.html", context=render_context)

@app.get("/api/lookup/{ip}")
def fetch_mac_from_cache(ip: str):
    mac_address = network.resolve_ip_to_mac(ip.strip())
    if mac_address:
        return {"success": True, "mac": mac_address}
    return {"success": False, "error": "Endpoint mapping not found."}

@app.post("/api/add")
async def web_add_device(alias: str = Form(...), mac: str = Form(...), ip: str = Form(...), os_type: str = Form(...), ssh_user: str = Form(None)):
    devices = load_devices()
    
    # 1. Clean and normalize the incoming values
    target_alias = alias.lower().strip()
    target_ip = ip.strip()
    target_mac = mac.upper().strip().replace("-", ":")
    target_os = os_type.lower().strip()
    target_ssh_user = ssh_user.strip() if ssh_user else ""
    
    # 2. Check for duplicate parameters across existing database layers
    for existing_alias, info in devices.items():
        # Prevent the user from hijacking an existing custom alias name
        if existing_alias == target_alias:
            return JSONResponse(
                status_code=400,
                content={"success": False, "error": f"The profile name '{alias}' is already taken."}
            )
        
        # Prevent duplicate IP configurations
        if info["ip"] == target_ip:
            return JSONResponse(
                status_code=400,
                content={"success": False, "error": f"The network IP '{target_ip}' is already assigned to the '{existing_alias}' profile."}
            )
            
        # Prevent duplicate hardware MAC profiles
        if info["mac"] == target_mac:
            return JSONResponse(
                status_code=400,
                content={"success": False, "error": f"The physical MAC address '{target_mac}' is already registered to the '{existing_alias}' profile."}
            )

    # 3. If everything is clear, commit the record to your local file
    devices[target_alias] = {
        "ip": target_ip,
        "mac": target_mac,
        "os_type": target_os,
        "ssh_user": target_ssh_user
    }
    save_devices(devices)
    return RedirectResponse(url="/", status_code=303)

@app.post("/api/delete/{alias}")
async def web_delete_device(alias: str):
    devices = load_devices()
    if alias.lower() in devices:
        del devices[alias.lower()]
        save_devices(devices)
    return RedirectResponse(url="/", status_code=303)

@app.post("/api/wake/{alias}")
async def web_wake_device(alias: str, username: str = Form(None), password: str = Form(None), remember: str = Form(None)):
    global SESSION_USER, SESSION_PASS
    devices = load_devices()
    target = alias.lower()
    
    user = username.strip() if username else SESSION_USER
    text_pass = password if password else SESSION_PASS
    
    if not user or not text_pass:
        return RedirectResponse(url="/", status_code=303)

    if remember == "true" and username and password:
        SESSION_USER = username.strip()
        SESSION_PASS = password

    if target in devices:
        network.send_wol_packet(devices[target]["mac"])
        
    return RedirectResponse(url="/", status_code=303)

def execute_winrm_sleep(ip, user, text_pass):
    sleep_payload = (
        "$rundll = '[DllImport(\"powrprof.dll\")] public static extern bool SetSuspendState(bool hiber, bool force, bool disable);'; "
        "$type = Add-Type -MemberDefinition $rundll -Name \"Win32Power\" -Namespace \"Win32\" -PassThru; "
        "$type::SetSuspendState($false, $false, $false)"
    )
    try:
        import winrm
        session = winrm.Session(ip, auth=(user, text_pass), transport='ntlm', read_timeout_sec=8, operation_timeout_sec=4)
        session.run_ps(sleep_payload)
    except:
        pass

@app.post("/api/sleep/{alias}")
async def web_sleep_device(alias: str, bg_tasks: BackgroundTasks, username: str = Form(None), password: str = Form(None), remember: str = Form(None)):
    global SESSION_USER, SESSION_PASS
    devices = load_devices()
    target = alias.lower()
    
    if target not in devices:
        return RedirectResponse(url="/", status_code=303)
        
    device_info = devices[target]
    
    if device_info.get("os_type") == "linux":
        username_target = device_info.get("ssh_user", "root")
        bg_tasks.add_task(network.execute_linux_ssh_sleep, device_info["ip"], username_target)
        return RedirectResponse(url="/", status_code=303)
        
    user = username.strip() if username else SESSION_USER
    text_pass = password if password else SESSION_PASS
    
    if not user or not text_pass:
        return RedirectResponse(url="/", status_code=303)

    if remember == "true" and username and password:
        SESSION_USER = username.strip()
        SESSION_PASS = password

    bg_tasks.add_task(execute_winrm_sleep, device_info["ip"], user, text_pass)
    return RedirectResponse(url="/", status_code=303)
