#!/usr/bin/env python3
from flask import Flask, render_template, jsonify
import psutil
from datetime import datetime

app = Flask(__name__)

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/status')
def get_status():
    try:
        cpu_percent = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        net_io = psutil.net_io_counters()

        # Check processes: Stardew (SMAPI), FRP, Supervisor
        processes = {}
        procs = list(psutil.process_iter(['name', 'cmdline']))
        def has_proc(match: str):
            m = match.lower()
            for p in procs:
                try:
                    name = (p.info.get('name') or '').lower()
                    cmd = ' '.join(p.info.get('cmdline') or []).lower()
                    if m in name or m in cmd:
                        return True
                except Exception:
                    continue
            return False

        processes['stardew'] = has_proc('StardewModdingAPI') or has_proc('stardewmoddingapi')
        processes['frpc'] = has_proc('frpc')
        processes['supervisord'] = has_proc('supervisord')

        boot_time = datetime.fromtimestamp(psutil.boot_time())
        uptime = str(datetime.now() - boot_time).split('.')[0]

        return jsonify({
            'cpu': {'percent': cpu_percent, 'count': psutil.cpu_count()},
            'memory': {'total': memory.total, 'used': memory.used, 'percent': memory.percent},
            'disk': {'total': disk.total, 'used': disk.used, 'percent': disk.percent},
            'network': {'sent': net_io.bytes_sent, 'recv': net_io.bytes_recv},
            'processes': processes,
            'uptime': uptime,
            'timestamp': datetime.now().isoformat(),
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=7860, debug=False)

