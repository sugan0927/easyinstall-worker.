#!/usr/bin/env python3
"""
EasyInstall WebUI - Enterprise Management Interface
"""

import os
import sys
import json
import subprocess
import threading
import time
import hashlib
import secrets
from datetime import datetime, timedelta
from functools import wraps
from flask import Flask, render_template, request, jsonify, session, redirect, url_for, flash, send_file
from flask_socketio import SocketIO, emit
import paramiko
import boto3
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
import redis
import logging
from logging.handlers import RotatingFileHandler
import sqlite3
import bcrypt

# Initialize Flask app
app = Flask(__name__)
app.config['SECRET_KEY'] = secrets.token_hex(32)
app.config['SESSION_TYPE'] = 'filesystem'
app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(hours=8)
socketio = SocketIO(app, cors_allowed_origins="*")

# Configuration
CONFIG_DIR = '/etc/easyinstall/webui'
DATA_DIR = '/var/lib/easyinstall/webui'
LOG_DIR = '/var/log/easyinstall'
BACKUP_DIR = '/backups'
TEMP_DIR = '/tmp/easyinstall-webui'

# Create directories
for dir_path in [CONFIG_DIR, DATA_DIR, LOG_DIR, TEMP_DIR]:
    os.makedirs(dir_path, exist_ok=True)

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        RotatingFileHandler(f'{LOG_DIR}/webui.log', maxBytes=10485760, backupCount=10),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('EasyInstallWebUI')

# Database setup
DB_PATH = f'{DATA_DIR}/users.db'

def init_db():
    """Initialize SQLite database"""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    
    # Users table
    c.execute('''CREATE TABLE IF NOT EXISTS users
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  username TEXT UNIQUE NOT NULL,
                  password_hash TEXT NOT NULL,
                  email TEXT,
                  role TEXT DEFAULT 'admin',
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  last_login TIMESTAMP,
                  twofa_secret TEXT,
                  twofa_enabled BOOLEAN DEFAULT 0)''')
    
    # Sessions table
    c.execute('''CREATE TABLE IF NOT EXISTS sessions
                 (id TEXT PRIMARY KEY,
                  user_id INTEGER,
                  expires TIMESTAMP,
                  ip_address TEXT,
                  user_agent TEXT,
                  FOREIGN KEY(user_id) REFERENCES users(id))''')
    
    # Cloud credentials table
    c.execute('''CREATE TABLE IF NOT EXISTS cloud_credentials
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  user_id INTEGER,
                  provider TEXT NOT NULL,
                  credentials TEXT NOT NULL,
                  name TEXT,
                  is_default BOOLEAN DEFAULT 0,
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  FOREIGN KEY(user_id) REFERENCES users(id))''')
    
    # Backup jobs table
    c.execute('''CREATE TABLE IF NOT EXISTS backup_jobs
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  name TEXT NOT NULL,
                  type TEXT NOT NULL,
                  source TEXT,
                  destination TEXT,
                  schedule TEXT,
                  retention_days INTEGER DEFAULT 30,
                  last_run TIMESTAMP,
                  next_run TIMESTAMP,
                  status TEXT DEFAULT 'active',
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  user_id INTEGER,
                  FOREIGN KEY(user_id) REFERENCES users(id))''')
    
    # Backup history table
    c.execute('''CREATE TABLE IF NOT EXISTS backup_history
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  job_id INTEGER,
                  start_time TIMESTAMP,
                  end_time TIMESTAMP,
                  size INTEGER,
                  status TEXT,
                  message TEXT,
                  location TEXT,
                  FOREIGN KEY(job_id) REFERENCES backup_jobs(id))''')
    
    # Domains table
    c.execute('''CREATE TABLE IF NOT EXISTS domains
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  domain TEXT UNIQUE NOT NULL,
                  type TEXT NOT NULL,
                  status TEXT DEFAULT 'active',
                  php_version TEXT,
                  ssl_enabled BOOLEAN DEFAULT 0,
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  user_id INTEGER,
                  FOREIGN KEY(user_id) REFERENCES users(id))''')
    
    # Settings table
    c.execute('''CREATE TABLE IF NOT EXISTS settings
                 (key TEXT PRIMARY KEY,
                  value TEXT,
                  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)''')
    
    # Create default admin user if not exists
    default_password = secrets.token_urlsafe(12)
    password_hash = bcrypt.hashpw(default_password.encode('utf-8'), bcrypt.gensalt())
    
    try:
        c.execute("INSERT OR IGNORE INTO users (username, password_hash, role) VALUES (?, ?, ?)",
                 ('admin', password_hash, 'admin'))
        conn.commit()
        
        # Save default password to file
        with open(f'{DATA_DIR}/admin_credentials.txt', 'w') as f:
            f.write(f"Username: admin\nPassword: {default_password}\n")
        os.chmod(f'{DATA_DIR}/admin_credentials.txt', 0o600)
    except:
        pass
    
    conn.close()

init_db()

# ============================================
# Authentication Decorators
# ============================================

def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user_id' not in session:
            return jsonify({'error': 'Authentication required'}), 401
        return f(*args, **kwargs)
    return decorated_function

def admin_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user_id' not in session:
            return jsonify({'error': 'Authentication required'}), 401
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("SELECT role FROM users WHERE id = ?", (session['user_id'],))
        result = c.fetchone()
        conn.close()
        if not result or result[0] != 'admin':
            return jsonify({'error': 'Admin privileges required'}), 403
        return f(*args, **kwargs)
    return decorated_function

# ============================================
# Routes - Web Interface
# ============================================

@app.route('/')
def index():
    """Main WebUI page"""
    if 'user_id' in session:
        return render_template('dashboard.html')
    return redirect(url_for('login'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    """Login page"""
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        remember = request.form.get('remember', False)
        
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("SELECT id, password_hash, role FROM users WHERE username = ?", (username,))
        user = c.fetchone()
        
        if user and bcrypt.checkpw(password.encode('utf-8'), user[1]):
            session['user_id'] = user[0]
            session['username'] = username
            session['role'] = user[2]
            
            if remember:
                session.permanent = True
            
            # Update last login
            c.execute("UPDATE users SET last_login = ? WHERE id = ?", 
                     (datetime.now().isoformat(), user[0]))
            conn.commit()
            
            # Log login
            logger.info(f"User {username} logged in from {request.remote_addr}")
            
            return jsonify({'success': True, 'redirect': '/'})
        
        conn.close()
        return jsonify({'success': False, 'error': 'Invalid credentials'}), 401
    
    return render_template('login.html')

@app.route('/logout')
def logout():
    """Logout user"""
    session.clear()
    return redirect(url_for('login'))

@app.route('/api/status')
@login_required
def system_status():
    """Get system status"""
    try:
        # System info
        status = {
            'system': {},
            'services': {},
            'domains': [],
            'backups': {},
            'resources': {}
        }
        
        # System info
        with open('/proc/loadavg') as f:
            load = f.read().strip().split()
            status['system']['load'] = load[:3]
        
        # Memory
        with open('/proc/meminfo') as f:
            meminfo = {}
            for line in f:
                if 'MemTotal' in line or 'MemFree' in line or 'MemAvailable' in line:
                    parts = line.split()
                    meminfo[parts[0].strip(':')] = int(parts[1])
            status['resources']['memory'] = meminfo
        
        # Disk
        df = subprocess.check_output(['df', '-h', '/']).decode().split('\n')[1].split()
        status['resources']['disk'] = {
            'size': df[1],
            'used': df[2],
            'available': df[3],
            'use_percent': df[4]
        }
        
        # Services
        services = ['nginx', 'mariadb', 'redis-server', 'memcached', 'fail2ban', 'php*-fpm']
        for service in services:
            try:
                result = subprocess.run(['systemctl', 'is-active', service], 
                                      capture_output=True, text=True)
                status['services'][service] = result.stdout.strip()
            except:
                status['services'][service] = 'inactive'
        
        # Domains from database
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("SELECT domain, type, ssl_enabled, created_at FROM domains WHERE status='active'")
        domains = c.fetchall()
        conn.close()
        
        for domain in domains:
            status['domains'].append({
                'name': domain[0],
                'type': domain[1],
                'ssl': bool(domain[2]),
                'created': domain[3]
            })
        
        # Backup stats
        backup_dir = BACKUP_DIR
        if os.path.exists(backup_dir):
            total_backups = 0
            total_size = 0
            for root, dirs, files in os.walk(backup_dir):
                total_backups += len(files)
                for file in files:
                    total_size += os.path.getsize(os.path.join(root, file))
            status['backups']['count'] = total_backups
            status['backups']['size'] = total_size
        
        return jsonify(status)
    
    except Exception as e:
        logger.error(f"Error getting system status: {e}")
        return jsonify({'error': str(e)}), 500

# ============================================
# Domain Management
# ============================================

@app.route('/api/domains', methods=['GET'])
@login_required
def list_domains():
    """List all domains"""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT * FROM domains ORDER BY created_at DESC")
    domains = c.fetchall()
    conn.close()
    
    result = []
    for d in domains:
        result.append({
            'id': d[0],
            'domain': d[1],
            'type': d[2],
            'status': d[3],
            'php_version': d[4],
            'ssl': bool(d[5]),
            'created': d[6]
        })
    
    return jsonify(result)

@app.route('/api/domains', methods=['POST'])
@login_required
def create_domain():
    """Create new domain/site"""
    data = request.json
    domain = data.get('domain')
    site_type = data.get('type', 'wordpress')
    ssl = data.get('ssl', False)
    php_version = data.get('php_version', '8.2')
    
    # Run easyinstall command
    try:
        cmd = ['easyinstall', 'create', domain]
        if ssl:
            cmd.append('--ssl')
        
        if site_type == 'php':
            cmd.append('--php')
        elif site_type == 'html':
            cmd.append('--html')
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            # Save to database
            conn = sqlite3.connect(DB_PATH)
            c = conn.cursor()
            c.execute('''INSERT INTO domains (domain, type, php_version, ssl_enabled, user_id)
                        VALUES (?, ?, ?, ?, ?)''',
                     (domain, site_type, php_version, ssl, session['user_id']))
            conn.commit()
            conn.close()
            
            logger.info(f"Domain created: {domain}")
            return jsonify({'success': True, 'output': result.stdout})
        else:
            return jsonify({'success': False, 'error': result.stderr}), 400
    
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/domains/<domain>/ssl', methods=['POST'])
@login_required
def enable_ssl(domain):
    """Enable SSL for domain"""
    try:
        result = subprocess.run(['easyinstall', 'site', domain, '--ssl=on'], 
                               capture_output=True, text=True)
        
        if result.returncode == 0:
            conn = sqlite3.connect(DB_PATH)
            c = conn.cursor()
            c.execute("UPDATE domains SET ssl_enabled = 1 WHERE domain = ?", (domain,))
            conn.commit()
            conn.close()
            
            return jsonify({'success': True, 'output': result.stdout})
        else:
            return jsonify({'success': False, 'error': result.stderr}), 400
    
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/domains/<domain>', methods=['DELETE'])
@login_required
def delete_domain(domain):
    """Delete domain"""
    try:
        # First, check if it's a Docker site
        docker_path = f"/opt/easyinstall/docker/{domain}"
        if os.path.exists(docker_path):
            result = subprocess.run(['easyinstall', 'docker', 'wordpress', 'delete', domain],
                                   capture_output=True, text=True)
        else:
            result = subprocess.run(['rm', '-rf', f"/var/www/html/{domain}"], 
                                   capture_output=True, text=True)
            subprocess.run(['rm', '-f', f"/etc/nginx/sites-available/{domain}"])
            subprocess.run(['rm', '-f', f"/etc/nginx/sites-enabled/{domain}"])
            subprocess.run(['systemctl', 'reload', 'nginx'])
        
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("UPDATE domains SET status = 'deleted' WHERE domain = ?", (domain,))
        conn.commit()
        conn.close()
        
        return jsonify({'success': True})
    
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

# ============================================
# Backup Management with Cloud Integration
# ============================================

class CloudBackupManager:
    """Manage backups to cloud providers"""
    
    def __init__(self, user_id):
        self.user_id = user_id
        self.conn = sqlite3.connect(DB_PATH)
        self.c = self.conn.cursor()
    
    def get_credentials(self, provider, default=False):
        """Get cloud credentials"""
        if default:
            self.c.execute('''SELECT credentials FROM cloud_credentials 
                            WHERE user_id = ? AND is_default = 1''', (self.user_id,))
        else:
            self.c.execute('''SELECT credentials FROM cloud_credentials 
                            WHERE user_id = ? AND provider = ?''', (self.user_id, provider))
        result = self.c.fetchone()
        if result:
            return json.loads(result[0])
        return None
    
    def save_credentials(self, provider, credentials, name=None, make_default=False):
        """Save cloud credentials"""
        cred_json = json.dumps(credentials)
        
        if make_default:
            self.c.execute('''UPDATE cloud_credentials SET is_default = 0 
                            WHERE user_id = ?''', (self.user_id,))
        
        self.c.execute('''INSERT OR REPLACE INTO cloud_credentials 
                        (user_id, provider, credentials, name, is_default)
                        VALUES (?, ?, ?, ?, ?)''',
                     (self.user_id, provider, cred_json, name, make_default))
        self.conn.commit()
    
    def backup_to_s3(self, backup_file, bucket_name, prefix=''):
        """Upload backup to S3"""
        creds = self.get_credentials('s3')
        if not creds:
            raise Exception("S3 credentials not configured")
        
        s3 = boto3.client(
            's3',
            aws_access_key_id=creds['access_key'],
            aws_secret_access_key=creds['secret_key'],
            region_name=creds.get('region', 'us-east-1')
        )
        
        key = f"{prefix}/{os.path.basename(backup_file)}"
        s3.upload_file(backup_file, bucket_name, key)
        
        return f"s3://{bucket_name}/{key}"
    
    def backup_to_gdrive(self, backup_file, folder_id=None):
        """Upload backup to Google Drive"""
        creds = self.get_credentials('gdrive')
        if not creds:
            raise Exception("Google Drive credentials not configured")
        
        from google.oauth2.credentials import Credentials
        from googleapiclient.discovery import build
        from googleapiclient.http import MediaFileUpload
        
        g_creds = Credentials.from_authorized_user_info(creds)
        service = build('drive', 'v3', credentials=g_creds)
        
        file_metadata = {'name': os.path.basename(backup_file)}
        if folder_id:
            file_metadata['parents'] = [folder_id]
        
        media = MediaFileUpload(backup_file, resumable=True)
        file = service.files().create(body=file_metadata, media_body=media, fields='id').execute()
        
        return f"gdrive://{file.get('id')}"
    
    def backup_to_rclone(self, backup_file, remote_name, remote_path):
        """Upload backup using rclone"""
        cmd = ['rclone', 'copy', backup_file, f"{remote_name}:{remote_path}"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            raise Exception(f"Rclone failed: {result.stderr}")
        
        return f"rclone://{remote_name}:{remote_path}/{os.path.basename(backup_file)}"
    
    def create_backup(self, job_id=None):
        """Create and upload backup"""
        timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        backup_file = f"{TEMP_DIR}/backup-{timestamp}.tar.gz"
        
        # Create backup
        subprocess.run(['easyinstall', 'backup', '--output', backup_file], check=True)
        
        # Upload to cloud if configured
        locations = []
        
        # Check for default cloud destination
        dest = self.c.execute('''SELECT destination FROM backup_jobs WHERE id = ?''', (job_id,)).fetchone()
        if dest and dest[0]:
            dest_config = json.loads(dest[0])
            for provider, config in dest_config.items():
                try:
                    if provider == 's3':
                        url = self.backup_to_s3(backup_file, config['bucket'], config.get('prefix', ''))
                    elif provider == 'gdrive':
                        url = self.backup_to_gdrive(backup_file, config.get('folder_id'))
                    elif provider == 'rclone':
                        url = self.backup_to_rclone(backup_file, config['remote'], config['path'])
                    
                    locations.append(url)
                    logger.info(f"Backup uploaded to {provider}: {url}")
                except Exception as e:
                    logger.error(f"Failed to upload to {provider}: {e}")
        
        # Save to backup history
        file_size = os.path.getsize(backup_file)
        locations_json = json.dumps(locations)
        
        self.c.execute('''INSERT INTO backup_history 
                        (job_id, start_time, end_time, size, status, location)
                        VALUES (?, ?, ?, ?, ?, ?)''',
                     (job_id, timestamp, datetime.now().isoformat(), 
                      file_size, 'completed', locations_json))
        self.conn.commit()
        
        return backup_file, locations

@app.route('/api/backups/create', methods=['POST'])
@login_required
def create_backup():
    """Create a new backup"""
    data = request.json
    backup_type = data.get('type', 'full')
    cloud_backup = data.get('cloud_backup', True)
    
    try:
        manager = CloudBackupManager(session['user_id'])
        backup_file, locations = manager.create_backup()
        
        return jsonify({
            'success': True,
            'file': backup_file,
            'size': os.path.getsize(backup_file),
            'locations': locations
        })
    
    except Exception as e:
        logger.error(f"Backup failed: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/backups/list', methods=['GET'])
@login_required
def list_backups():
    """List all backups"""
    backups = []
    
    # Local backups
    if os.path.exists(BACKUP_DIR):
        for root, dirs, files in os.walk(BACKUP_DIR):
            for file in files:
                if file.endswith('.tar.gz') or file.endswith('.sql'):
                    path = os.path.join(root, file)
                    backups.append({
                        'name': file,
                        'path': path,
                        'size': os.path.getsize(path),
                        'modified': datetime.fromtimestamp(os.path.getmtime(path)).isoformat(),
                        'type': 'local'
                    })
    
    # Cloud backup history
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''SELECT * FROM backup_history ORDER BY start_time DESC LIMIT 50''')
    history = c.fetchall()
    conn.close()
    
    for h in history:
        backups.append({
            'id': h[0],
            'start_time': h[2],
            'end_time': h[3],
            'size': h[4],
            'status': h[5],
            'message': h[6],
            'locations': json.loads(h[7]) if h[7] else [],
            'type': 'cloud'
        })
    
    return jsonify(backups)

@app.route('/api/backups/jobs', methods=['GET'])
@login_required
def list_backup_jobs():
    """List backup jobs"""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''SELECT * FROM backup_jobs WHERE user_id = ? ORDER BY created_at DESC''', 
             (session['user_id'],))
    jobs = c.fetchall()
    conn.close()
    
    result = []
    for job in jobs:
        result.append({
            'id': job[0],
            'name': job[1],
            'type': job[2],
            'source': job[3],
            'destination': json.loads(job[4]) if job[4] else {},
            'schedule': job[5],
            'retention_days': job[6],
            'last_run': job[7],
            'next_run': job[8],
            'status': job[9]
        })
    
    return jsonify(result)

@app.route('/api/backups/jobs', methods=['POST'])
@login_required
def create_backup_job():
    """Create a scheduled backup job"""
    data = request.json
    
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''INSERT INTO backup_jobs 
                (name, type, source, destination, schedule, retention_days, user_id)
                VALUES (?, ?, ?, ?, ?, ?, ?)''',
             (data['name'], data['type'], data.get('source'), 
              json.dumps(data.get('destination', {})),
              data.get('schedule'), data.get('retention_days', 30), 
              session['user_id']))
    conn.commit()
    conn.close()
    
    return jsonify({'success': True})

# ============================================
# Cloud Storage Configuration
# ============================================

@app.route('/api/cloud/configure/<provider>', methods=['POST'])
@login_required
def configure_cloud(provider):
    """Configure cloud storage provider"""
    data = request.json
    manager = CloudBackupManager(session['user_id'])
    
    try:
        if provider == 's3':
            credentials = {
                'access_key': data['access_key'],
                'secret_key': data['secret_key'],
                'region': data.get('region', 'us-east-1')
            }
        elif provider == 'gdrive':
            credentials = {
                'token': data['token'],
                'refresh_token': data.get('refresh_token'),
                'token_uri': 'https://oauth2.googleapis.com/token',
                'client_id': data['client_id'],
                'client_secret': data['client_secret'],
                'scopes': ['https://www.googleapis.com/auth/drive.file']
            }
        elif provider == 'rclone':
            credentials = {
                'remote': data['remote'],
                'type': data.get('type', 'drive')
            }
        else:
            return jsonify({'success': False, 'error': 'Unknown provider'}), 400
        
        manager.save_credentials(
            provider, 
            credentials, 
            name=data.get('name'),
            make_default=data.get('default', False)
        )
        
        return jsonify({'success': True})
    
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/cloud/status', methods=['GET'])
@login_required
def cloud_status():
    """Get cloud storage status"""
    manager = CloudBackupManager(session['user_id'])
    
    providers = ['s3', 'gdrive', 'rclone']
    status = {}
    
    for provider in providers:
        creds = manager.get_credentials(provider)
        status[provider] = {
            'configured': creds is not None,
            'default': False
        }
        
        # Check if default
        default = manager.get_credentials(provider, default=True)
        if default and creds == default:
            status[provider]['default'] = True
    
    return jsonify(status)

# ============================================
# Docker Management
# ============================================

@app.route('/api/docker/installations', methods=['GET'])
@login_required
def list_docker_installations():
    """List Docker WordPress installations"""
    installations = []
    
    docker_base = '/opt/easyinstall/docker'
    if os.path.exists(docker_base):
        for domain in os.listdir(docker_base):
            path = os.path.join(docker_base, domain)
            if os.path.isdir(path) and os.path.exists(os.path.join(path, 'docker-compose.yml')):
                # Get container status
                try:
                    result = subprocess.run(
                        ['docker-compose', '-f', f'{path}/docker-compose.yml', 'ps', '--format', 'json'],
                        capture_output=True, text=True, cwd=path
                    )
                    containers = json.loads(result.stdout) if result.stdout else []
                    
                    status = 'running'
                    for container in containers:
                        if 'Up' not in container.get('Status', ''):
                            status = 'partial'
                            break
                except:
                    status = 'unknown'
                
                installations.append({
                    'domain': domain,
                    'path': path,
                    'status': status,
                    'type': 'docker'
                })
    
    return jsonify(installations)

@app.route('/api/docker/install', methods=['POST'])
@login_required
def install_docker_wordpress():
    """Install WordPress in Docker"""
    data = request.json
    domain = data.get('domain')
    ssl = data.get('ssl', False)
    
    try:
        # Run docker installation
        cmd = ['easyinstall', 'docker', 'wordpress', 'install', domain]
        if ssl:
            cmd.append('--ssl')
        
        # Run in background
        def run_install():
            result = subprocess.run(cmd, capture_output=True, text=True)
            socketio.emit('docker_install_complete', {
                'domain': domain,
                'success': result.returncode == 0,
                'output': result.stdout if result.returncode == 0 else result.stderr
            })
        
        thread = threading.Thread(target=run_install)
        thread.daemon = True
        thread.start()
        
        return jsonify({'success': True, 'message': 'Installation started'})
    
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

# ============================================
# System Commands
# ============================================

@app.route('/api/command/<cmd>', methods=['POST'])
@login_required
def run_command(cmd):
    """Run easyinstall command"""
    data = request.json
    args = data.get('args', [])
    
    try:
        full_cmd = ['easyinstall', cmd] + args
        result = subprocess.run(full_cmd, capture_output=True, text=True)
        
        return jsonify({
            'success': result.returncode == 0,
            'stdout': result.stdout,
            'stderr': result.stderr
        })
    
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/service/<name>/<action>', methods=['POST'])
@login_required
def service_action(name, action):
    """Control system services"""
    try:
        if action in ['start', 'stop', 'restart', 'reload', 'status']:
            result = subprocess.run(['systemctl', action, name], capture_output=True, text=True)
            return jsonify({
                'success': result.returncode == 0,
                'output': result.stdout,
                'error': result.stderr
            })
        else:
            return jsonify({'success': False, 'error': 'Invalid action'}), 400
    
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

# ============================================
# Real-time Updates
# ============================================

@socketio.on('connect')
def handle_connect():
    """Handle client connection"""
    emit('connected', {'data': 'Connected to EasyInstall WebUI'})

@socketio.on('subscribe_status')
def handle_status_subscribe():
    """Subscribe to real-time status updates"""
    def status_updater():
        while True:
            # Get system stats
            stats = {
                'timestamp': datetime.now().isoformat(),
                'cpu': get_cpu_usage(),
                'memory': get_memory_usage(),
                'disk': get_disk_usage(),
                'services': get_services_status()
            }
            socketio.emit('status_update', stats)
            time.sleep(5)
    
    thread = threading.Thread(target=status_updater)
    thread.daemon = True
    thread.start()

def get_cpu_usage():
    """Get CPU usage percentage"""
    with open('/proc/stat') as f:
        line = f.readline().split()
        total = sum(int(x) for x in line[1:])
        idle = int(line[4])
    return {'total': total, 'idle': idle}

def get_memory_usage():
    """Get memory usage"""
    with open('/proc/meminfo') as f:
        meminfo = {}
        for line in f:
            if 'MemTotal' in line or 'MemFree' in line or 'MemAvailable' in line:
                parts = line.split()
                meminfo[parts[0].strip(':')] = int(parts[1])
    return meminfo

def get_disk_usage():
    """Get disk usage"""
    df = subprocess.check_output(['df', '-h', '/']).decode().split('\n')[1].split()
    return {
        'size': df[1],
        'used': df[2],
        'available': df[3],
        'use_percent': df[4]
    }

def get_services_status():
    """Get services status"""
    services = {}
    for service in ['nginx', 'mariadb', 'redis-server', 'memcached', 'fail2ban', 'php*-fpm']:
        try:
            result = subprocess.run(['systemctl', 'is-active', service], 
                                  capture_output=True, text=True)
            services[service] = result.stdout.strip()
        except:
            services[service] = 'inactive'
    return services

# ============================================
# User Management
# ============================================

@app.route('/api/users', methods=['GET'])
@admin_required
def list_users():
    """List all users"""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT id, username, email, role, created_at, last_login FROM users")
    users = c.fetchall()
    conn.close()
    
    result = []
    for user in users:
        result.append({
            'id': user[0],
            'username': user[1],
            'email': user[2],
            'role': user[3],
            'created_at': user[4],
            'last_login': user[5]
        })
    
    return jsonify(result)

@app.route('/api/users', methods=['POST'])
@admin_required
def create_user():
    """Create new user"""
    data = request.json
    username = data.get('username')
    password = data.get('password')
    email = data.get('email')
    role = data.get('role', 'user')
    
    password_hash = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
    
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    
    try:
        c.execute('''INSERT INTO users (username, password_hash, email, role)
                    VALUES (?, ?, ?, ?)''',
                 (username, password_hash, email, role))
        conn.commit()
        return jsonify({'success': True})
    except sqlite3.IntegrityError:
        return jsonify({'success': False, 'error': 'Username already exists'}), 400
    finally:
        conn.close()

@app.route('/api/users/<int:user_id>', methods=['DELETE'])
@admin_required
def delete_user(user_id):
    """Delete user"""
    if user_id == session['user_id']:
        return jsonify({'success': False, 'error': 'Cannot delete yourself'}), 400
    
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("DELETE FROM users WHERE id = ?", (user_id,))
    conn.commit()
    conn.close()
    
    return jsonify({'success': True})

# ============================================
# Settings
# ============================================

@app.route('/api/settings', methods=['GET'])
@login_required
def get_settings():
    """Get settings"""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT key, value FROM settings")
    settings = dict(c.fetchall())
    conn.close()
    
    return jsonify(settings)

@app.route('/api/settings', methods=['POST'])
@login_required
def update_settings():
    """Update settings"""
    data = request.json
    
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    
    for key, value in data.items():
        c.execute('''INSERT OR REPLACE INTO settings (key, value, updated_at)
                    VALUES (?, ?, ?)''',
                 (key, value, datetime.now().isoformat()))
    
    conn.commit()
    conn.close()
    
    return jsonify({'success': True})

# ============================================
# Main Entry Point
# ============================================

if __name__ == '__main__':
    socketio.run(app, host='0.0.0.0', port=5000, debug=False)
