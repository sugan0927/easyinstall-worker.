// src/index.ts - COMPLETELY FIXED VERSION
// DO NOT use destructured import - use namespace import

import { Hono } from 'hono';
import { serve } from 'std/http/server.ts';
// IMPORTANT: Use namespace import, NOT destructured
import ssh2 from 'ssh2';

// Type definitions
interface Deployment {
  id: string;
  domain: string;
  serverIp: string;
  sshPort: number;
  sshUser: string;
  template: string;
  status: 'pending' | 'running' | 'completed' | 'failed';
  startTime: string;
  endTime?: string;
  error?: string;
  logs: string[];
}

// In-memory storage (will use Deno KV in production)
const deployments = new Map<string, Deployment>();

// Create Hono app
const app = new Hono();

// ============================================
// Serve HTML UI
// ============================================
app.get('/', (c) => {
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>EasyInstall Deno Deployer</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1e1e2f 0%, #2a2a40 100%);
            min-height: 100vh;
            color: white;
        }
        .container { max-width: 800px; margin: 0 auto; padding: 40px 20px; }
        .header { text-align: center; margin-bottom: 40px; }
        .header h1 { font-size: 3em; margin-bottom: 10px; }
        .header h1 span { color: #00ff00; }
        .card {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            margin-bottom: 20px;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .form-group { margin-bottom: 20px; }
        label {
            display: block;
            margin-bottom: 5px;
            font-weight: 600;
            color: #ccc;
        }
        input, select, textarea {
            width: 100%;
            padding: 12px;
            background: rgba(255,255,255,0.05);
            border: 2px solid rgba(255,255,255,0.1);
            border-radius: 8px;
            font-size: 16px;
            color: white;
            transition: border-color 0.3s;
        }
        input:focus, select:focus, textarea:focus {
            outline: none;
            border-color: #00ff00;
        }
        textarea {
            font-family: 'Monaco', 'Menlo', monospace;
            font-size: 14px;
        }
        button {
            background: linear-gradient(135deg, #00ff00 0%, #00cc00 100%);
            color: #1e1e2f;
            border: none;
            padding: 15px 30px;
            border-radius: 8px;
            font-size: 18px;
            font-weight: 600;
            cursor: pointer;
            width: 100%;
            transition: transform 0.2s;
        }
        button:hover { transform: translateY(-2px); }
        button:disabled { opacity: 0.5; cursor: not-allowed; }
        .log-output {
            background: #0a0a0a;
            color: #00ff00;
            padding: 20px;
            border-radius: 8px;
            font-family: 'Monaco', 'Menlo', monospace;
            font-size: 14px;
            height: 300px;
            overflow-y: auto;
            white-space: pre-wrap;
        }
        .status {
            padding: 15px;
            border-radius: 8px;
            margin-top: 20px;
            font-weight: 600;
        }
        .status-success { background: rgba(0,255,0,0.2); color: #00ff00; border: 1px solid #00ff00; }
        .status-error { background: rgba(255,0,0,0.2); color: #ff6b6b; border: 1px solid #ff6b6b; }
        .status-pending { background: rgba(255,255,0,0.2); color: #ffff00; border: 1px solid #ffff00; }
        .loading {
            display: inline-block;
            width: 20px;
            height: 20px;
            border: 3px solid rgba(255,255,255,.3);
            border-radius: 50%;
            border-top-color: white;
            animation: spin 1s ease-in-out infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
        .deployments-list {
            max-height: 300px;
            overflow-y: auto;
        }
        .deployment-item {
            background: rgba(255,255,255,0.05);
            padding: 15px;
            border-radius: 8px;
            margin-bottom: 10px;
            border-left: 4px solid #00ff00;
        }
        .deployment-item small { color: #ccc; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1><span>🦕</span> EasyInstall Deno Deployer</h1>
            <p>Deploy WordPress to your server with one click</p>
        </div>
        
        <div class="card">
            <h2>📦 New Deployment</h2>
            
            <form id="deployForm">
                <div class="form-group">
                    <label for="domain">Domain Name:</label>
                    <input type="text" id="domain" placeholder="example.com" required>
                </div>
                
                <div class="form-group">
                    <label for="serverIp">Server IP Address:</label>
                    <input type="text" id="serverIp" placeholder="192.168.1.100" required>
                </div>
                
                <div class="form-group">
                    <label for="sshPort">SSH Port:</label>
                    <input type="number" id="sshPort" value="22" required>
                </div>
                
                <div class="form-group">
                    <label for="sshUser">SSH Username:</label>
                    <input type="text" id="sshUser" value="root" required>
                </div>
                
                <div class="form-group">
                    <label for="sshKey">SSH Private Key:</label>
                    <textarea id="sshKey" rows="6" placeholder="-----BEGIN RSA PRIVATE KEY-----&#10;...&#10;-----END RSA PRIVATE KEY-----" required></textarea>
                </div>
                
                <div class="form-group">
                    <label for="template">Deployment Template:</label>
                    <select id="template">
                        <option value="basic">WordPress Basic</option>
                        <option value="ssl">WordPress with SSL</option>
                        <option value="multisite">Multi-site Setup</option>
                    </select>
                </div>
                
                <button type="submit" id="deployBtn">
                    <span id="btnText">🚀 Start Deployment</span>
                    <span id="btnSpinner" class="loading" style="display: none;"></span>
                </button>
            </form>
            
            <div id="status" class="status" style="display: none;"></div>
            
            <div style="margin-top: 20px;">
                <h3>📋 Live Deployment Logs:</h3>
                <div id="logs" class="log-output">Waiting for deployment to start...</div>
            </div>
        </div>
        
        <div class="card">
            <h2>📊 Recent Deployments</h2>
            <div id="recentDeployments" class="deployments-list">
                <p style="color: #ccc;">Loading...</p>
            </div>
        </div>
    </div>
    
    <script>
        let currentDeploymentId = null;
        let logInterval = null;
        
        document.getElementById('deployForm').addEventListener('submit', async (e) => {
            e.preventDefault();
            
            const btn = document.getElementById('deployBtn');
            const btnText = document.getElementById('btnText');
            const btnSpinner = document.getElementById('btnSpinner');
            const statusDiv = document.getElementById('status');
            const logsDiv = document.getElementById('logs');
            
            btn.disabled = true;
            btnText.style.display = 'none';
            btnSpinner.style.display = 'inline-block';
            statusDiv.style.display = 'none';
            logsDiv.textContent = '🚀 Starting deployment...\\n';
            
            try {
                const response = await fetch('/api/deploy', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        domain: document.getElementById('domain').value,
                        serverIp: document.getElementById('serverIp').value,
                        sshPort: parseInt(document.getElementById('sshPort').value),
                        sshUser: document.getElementById('sshUser').value,
                        sshKey: document.getElementById('sshKey').value,
                        template: document.getElementById('template').value
                    })
                });
                
                const data = await response.json();
                
                if (data.success) {
                    currentDeploymentId = data.deploymentId;
                    statusDiv.className = 'status status-pending';
                    statusDiv.textContent = \`✅ Deployment started! ID: \${currentDeploymentId}\`;
                    statusDiv.style.display = 'block';
                    
                    startLogPolling(currentDeploymentId);
                    document.getElementById('sshKey').value = '';
                } else {
                    throw new Error(data.error);
                }
                
            } catch (error) {
                statusDiv.className = 'status status-error';
                statusDiv.textContent = \`❌ Error: \${error.message}\`;
                statusDiv.style.display = 'block';
                logsDiv.textContent += \`\\n❌ \${error.message}\`;
                
            } finally {
                btn.disabled = false;
                btnText.style.display = 'inline';
                btnSpinner.style.display = 'none';
            }
        });
        
        function startLogPolling(id) {
            if (logInterval) clearInterval(logInterval);
            
            logInterval = setInterval(async () => {
                try {
                    const response = await fetch(\`/api/status?id=\${id}\`);
                    const data = await response.json();
                    
                    const logsDiv = document.getElementById('logs');
                    if (data.logs) {
                        logsDiv.textContent = data.logs.join('\\n');
                        logsDiv.scrollTop = logsDiv.scrollHeight;
                    }
                    
                    const statusDiv = document.getElementById('status');
                    
                    if (data.status === 'completed') {
                        clearInterval(logInterval);
                        statusDiv.className = 'status status-success';
                        statusDiv.textContent = '✅ Deployment completed successfully!';
                        loadRecentDeployments();
                    } else if (data.status === 'failed') {
                        clearInterval(logInterval);
                        statusDiv.className = 'status status-error';
                        statusDiv.textContent = \`❌ Deployment failed: \${data.error}\`;
                    }
                    
                } catch (error) {
                    console.error('Failed to fetch status:', error);
                }
            }, 2000);
        }
        
        async function loadRecentDeployments() {
            try {
                const response = await fetch('/api/deployments');
                const data = await response.json();
                
                const container = document.getElementById('recentDeployments');
                if (data.deployments && data.deployments.length > 0) {
                    container.innerHTML = data.deployments.map(d => \`
                        <div class="deployment-item">
                            <strong>\${d.domain}</strong> - 
                            <span class="badge" style="background: \${d.status === 'completed' ? '#00ff0022' : d.status === 'failed' ? '#ff000022' : '#ffff0022'}; color: \${d.status === 'completed' ? '#00ff00' : d.status === 'failed' ? '#ff6b6b' : '#ffff00'}; padding: 3px 8px; border-radius: 12px;">\${d.status}</span>
                            <br>
                            <small>Started: \${new Date(d.startTime).toLocaleString()}</small>
                        </div>
                    \`).join('');
                } else {
                    container.innerHTML = '<p style="color: #ccc;">No recent deployments</p>';
                }
            } catch (error) {
                console.error('Failed to load deployments:', error);
            }
        }
        
        loadRecentDeployments();
        setInterval(loadRecentDeployments, 10000);
    </script>
</body>
</html>`;
  
  return c.html(html);
});

// ============================================
// API: Start Deployment
// ============================================
app.post('/api/deploy', async (c) => {
  try {
    const { domain, serverIp, sshPort, sshUser, sshKey, template } = await c.req.json();
    
    if (!domain || !serverIp || !sshUser || !sshKey) {
      return c.json({ success: false, error: 'Missing required fields' }, 400);
    }
    
    const deploymentId = crypto.randomUUID();
    
    const deployment: Deployment = {
      id: deploymentId,
      domain,
      serverIp,
      sshPort: sshPort || 22,
      sshUser,
      template,
      status: 'pending',
      startTime: new Date().toISOString(),
      logs: [`[${new Date().toISOString()}] 🚀 Deployment started for ${domain}`]
    };
    
    deployments.set(deploymentId, deployment);
    
    // Execute deployment in background
    executeDeployment(deploymentId, domain, serverIp, sshPort || 22, sshUser, sshKey, template);
    
    return c.json({
      success: true,
      deploymentId,
      message: 'Deployment started'
    });
    
  } catch (error) {
    return c.json({ success: false, error: error.message }, 500);
  }
});

// ============================================
// API: Get Status
// ============================================
app.get('/api/status', (c) => {
  const deploymentId = c.req.query('id');
  
  if (!deploymentId) {
    return c.json({ error: 'Missing deployment ID' }, 400);
  }
  
  const deployment = deployments.get(deploymentId);
  
  if (!deployment) {
    return c.json({ error: 'Deployment not found' }, 404);
  }
  
  return c.json({
    status: deployment.status,
    logs: deployment.logs,
    startTime: deployment.startTime,
    endTime: deployment.endTime,
    error: deployment.error
  });
});

// ============================================
// API: Get All Deployments
// ============================================
app.get('/api/deployments', (c) => {
  const deploymentList = Array.from(deployments.values())
    .sort((a, b) => new Date(b.startTime).getTime() - new Date(a.startTime).getTime())
    .slice(0, 10);
  
  return c.json({ deployments: deploymentList });
});

// ============================================
// Execute SSH Deployment - FIXED
// ============================================
async function executeDeployment(
  deploymentId: string,
  domain: string,
  serverIp: string,
  sshPort: number,
  sshUser: string,
  sshKey: string,
  template: string
) {
  const log = (message: string) => {
    const deployment = deployments.get(deploymentId);
    if (deployment) {
      deployment.logs.push(`[${new Date().toISOString()}] ${message}`);
      deployments.set(deploymentId, deployment);
    }
    console.log(`[${deploymentId}] ${message}`);
  };
  
  try {
    const deployment = deployments.get(deploymentId);
    if (deployment) deployment.status = 'running';
    
    log('🔌 Establishing SSH connection...');
    
    // FIX: Use default import and access Client property
    const Client = ssh2.Client;
    const client = new Client();
    
    await new Promise((resolve, reject) => {
      client.on('ready', () => {
        log('✅ SSH connection established');
        
        // Build command based on template
        const easyinstallUrl = 'https://raw.githubusercontent.com/yourusername/easyinstall/main/easyinstall.sh';
        let command = '';
        
        switch (template) {
          case 'ssl':
            command = `curl -sSL ${easyinstallUrl} | bash && easyinstall domain ${domain} --ssl`;
            break;
          case 'multisite':
            command = `curl -sSL ${easyinstallUrl} | bash && easyinstall panel`;
            break;
          default:
            command = `curl -sSL ${easyinstallUrl} | bash && easyinstall domain ${domain}`;
        }
        
        log(`📦 Executing: ${command}`);
        
        client.exec(command, (err: Error | null, stream: any) => {
          if (err) {
            reject(err);
            return;
          }
          
          stream.on('close', (code: number) => {
            log(`✅ Process finished with code ${code}`);
            client.end();
            
            const deployment = deployments.get(deploymentId);
            if (deployment) {
              deployment.status = code === 0 ? 'completed' : 'failed';
              deployment.endTime = new Date().toISOString();
            }
            
            resolve(true);
          });
          
          stream.on('data', (data: Buffer) => {
            log(data.toString());
          });
          
          stream.stderr.on('data', (data: Buffer) => {
            log(`⚠️ ${data.toString()}`);
          });
        });
      });
      
      client.on('error', (err: Error) => {
        log(`❌ SSH Error: ${err.message}`);
        reject(err);
      });
      
      client.connect({
        host: serverIp,
        port: sshPort,
        username: sshUser,
        privateKey: sshKey,
        readyTimeout: 30000,
        keepaliveInterval: 10000
      });
    });
    
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    log(`❌ Deployment failed: ${errorMessage}`);
    
    const deployment = deployments.get(deploymentId);
    if (deployment) {
      deployment.status = 'failed';
      deployment.error = errorMessage;
      deployment.endTime = new Date().toISOString();
    }
  }
}

// ============================================
// Start server
// ============================================
serve(app.fetch, { port: 8000 });

console.log('🚀 EasyInstall server running on http://localhost:8000');
