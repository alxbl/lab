# Simple script to keep QBT in sync with gluetun's allocated port forward.

# Preconditions:
# - There is only one user/pass in the gluetun configuration.
# - gluetun's config path is stored in environment variable GLUETUN_CONFIG_PATH
# - QBT WebUI user is `admin` and password is stored in environment variable QBT_WEBUI_PASSWORD
# - gluetun API authentication method is `basic`.

# See /infra/examples/secrets/gluetun-config.yaml.

import os
import re
import json
from time import sleep

from requests import Session
from requests.auth import HTTPBasicAuth

GLUETUN_CONFIG_PATH = os.environ.get('GLUETUN_CONFIG_PATH') or '/etc/gluetun.toml'
GLUETUN_API_URL = os.environ.get('GLUETUN_API_URL') or 'http://localhost:8000'
QBT_WEBUI_PASSWORD = os.environ.get('QBT_WEBUI_PASSWORD') or ''
QBT_WEBUI_URL = os.environ.get('QBT_WEBUI_URL') or 'http://localhost:8080'

BAD_CREDS = False

# Get gluetun API creds.
gluetun_user = None
gluetun_pass = None
try:
    with open(GLUETUN_CONFIG_PATH, 'r') as f:
        for l in f.readlines():
            if "username" in l:
                gluetun_user = re.match('\\s*username\\s*=\\s*"([^"]+)"', l).group(1)
            if "password" in l:
                gluetun_pass = re.match('\\s*password\\s*=\\s*"([^"]+)"', l).group(1)

except:
    print("[!] Failed to parse gluetun configuration file")   
    raise

if None in [gluetun_user, gluetun_pass]:
    print('[!] gluetun: API user/password missing.')

gluetun_creds = HTTPBasicAuth(gluetun_user, gluetun_pass)

# Get gluetun forwarded port 
# ref: https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/control-server.md
GLUETUN = Session()

print('[*] pmpd: Port forwarding monitoring started')

while True:
    # Get port exposed by natpmpc.
    pmp_port = GLUETUN.get(f"{GLUETUN_API_URL}/v1/portforward", auth=gluetun_creds)
    mapped = None 
    try:
        mapped = json.loads(pmp_port.text)['port']
    except:
        print('[!] gluetun: Unable to get mapped port: ' + pmp_port.text)

    if BAD_CREDS:
        print('[!] qbt: Invalid API credentials!')
        continue

    # Always re-auth to ensure the session hasn't expired.
    QBT = Session()

    # ref: https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-4.1)#login
    login = QBT.post(f"{QBT_WEBUI_URL}/api/v2/auth/login", data={'username': 'admin', 'password': QBT_WEBUI_PASSWORD})

    if not login.ok or 'Fails' in login.text:  # For some reason subsequet failures return 200 OK?
        print('[!] qbt: Invalid API credentials: ' + login.text)
        BAD_CREDS = True  # Avoid retrying invalid creds and getting ip-banned.
    else:
        # Get the currently configured listening port
        resp = QBT.get(f"{QBT_WEBUI_URL}/api/v2/app/preferences")
        if not resp.ok:
            print('[!] qbt: Failed to retrieve qbt preferences: ' + resp.text)
        prefs = json.loads(resp.text)

        configured = prefs['listen_port']

        if configured != mapped and mapped not in [0, None]:
            print(f"[*] gluetun: New mapped port detected. {configured} -> {mapped}")
            data = json.dumps({'listen_port': mapped, 'upnp': False })
            update = QBT.post(f"{QBT_WEBUI_URL}/api/v2/app/setPreferences", data={'json': data})
            if not update.ok:
                print('[!] qbt: Failed to update listen port: ' + str(update.status_code))
        # else:
        #    print(f"[+] qbt: Listen port is up-to-date: {mapped}")

    sleep(60)
