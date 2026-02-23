import { Client } from 'ssh2';

export interface Env {
  MAX_DEPLOYMENTS: string;
  DEPLOYMENT_TIMEOUT: string;
  GITHUB_RAW_URL: string;
}

// In-memory storage (Worker has limits, consider using KV for production)
const deployments = new Map<string, any>();
const logs = new Map<string, string>();

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    // Serve HTML UI
    if (path === '/' || path === '') {
      return serveUI();
    }

    // API Routes
    if (path === '/api/deploy' && request.method === 'POST') {
      return handleDeploy(request, env, ctx);
    }

    if (path === '/api/status' && request.method === 'GET') {
      const deploymentId = url.searchParams.get('id');
      return handleStatus(deploymentId);
    }

    if (path === '/api/logs' && request.method === 'GET') {
      const deploymentId = url.searchParams.get('id');
      return handleLogs(deploymentId);
    }

    if (path === '/api/templates' && request.method === 'GET') {
      return handleTemplates();
    }

    return new Response('Not Found', { status: 404 });
  },
};

// ============================================
// Serve the HTML UI
// ============================================
function serveUI(): Response {
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>EasyInstall Deployer</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: white;
        }
        .container { max-width: 800px; margin: 0 auto; padding: 40px 20px; }
        .header { text-align: center; margin-bottom: 40px; }
        .header h1 { font-size: 3em; margin-bottom: 10px; }
        .card {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 15px;
            padding: 30px;
            color: #333;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            margin-bottom: 20px;
        }
        .form-group { margin-bottom: 20px; }
        label {
            display: block;
            margin-bottom: 5px;
            font-weight: 600;
            color: #555;
        }
        input, select, textarea {
            width: 100%;
            padding: 12px;
            border: 2px solid #e0e0e0;
            border-radius: 8px;
            font-size: 16px;
            transition: border-color 0.3s;
        }
        input:focus, select:focus, textarea:focus {
            outline: none;
            border-color: #667eea;
        }
        textarea {
            font-family: 'Monaco', 'Menlo', monospace;
            font-size: 14px;
        }
        button {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
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
            background: #1e1e2f;
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
        .status-success { background: #d4edda; color: #155724; }
        .status-error { background: #f8d7da; color: #721c24; }
        .status-pending { background: #fff3cd; color: #856404; }
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
        .templates {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        .template-card {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            cursor: pointer;
            transition: all 0.3s;
            border: 2px solid transparent;
        }
        .template-card:hover {
            transform: translateY(-5px);
            border-color: #667eea;
        }
        .template-card h3 { color: #333; margin-bottom: 10px; }
        .template-card p { color: #666; font-size: 14px; }
        .badge {
            display: inline-block;
            padding: 5px 10px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
        }
        .badge-success { background: #d4edda; color: #155724; }
        .badge-warning { background: #fff3cd; color: #856404; }
        .badge-danger { background: #f8d7da; color: #721c24; }
        .deployments-list {
            margin-top: 20px;
            max-height: 300px;
            overflow-y: auto;
        }
        .deployment-item {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 8px;
            margin-bottom: 10px;
            border-left: 4px solid #667eea;
        }
        .deployment-item small { color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>馃殌 EasyInstall Deployer</h1>
            <p>Deploy WordPress to your server with one click</p>
        </div>
        
        <div class="card">
            <h2>馃摝 New Deployment</h2>
            
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
                    <span id="btnText">馃殌 Start Deployment</span>
                    <span id="btnSpinner" class="loading" style="display: none;"></span>
                </button>
            </form>
            
            <div id="status" class="status" style="display: none;"></div>
            
            <div style="margin-top: 20px;">
                <h3>馃搵 Live Deployment Logs:</h3>
                <div id="logs" class="log-output">Waiting for deployment to start...</div>
            </div>
        </div>
        
        <div class="card">
            <h2>鈿� Quick Templates</h2>
            <div class="templates" id="templates"></div>
        </div>
        
        <div class="card">
            <h2>馃搳 Recent Deployments</h2>
            <div id="recentDeployments" class="deployments-list">
                <p style="color: #666;">No recent deployments</p>
            </div>
        </div>
    </div>
    
    <script>
        // Store deployment IDs
        let currentDeploymentId = null;
        let logInterval = null;
        
        // Load templates on page load
        async function loadTemplates() {
            try {
                const response = await fetch('/api/templates');
                const data = await response.json();
                
                const container = document.getElementById('templates');
                container.innerHTML = data.templates.map(t => \`
                    <div class="template-card" onclick="applyTemplate('\${t.name}')">
                        <h3>\${t.name}</h3>
                        <p>\${t.description}</p>
                        <small>\${t.command}</small>
                    </div>
                \`).join('');
            } catch (error) {
                console.error('Failed to load templates:', error);
            }
        }
        
        function applyTemplate(templateName) {
            const select = document.getElementById('template');
            const options = {
                'WordPress Basic': 'basic',
                'WordPress with SSL': 'ssl',
                'Multi-site Setup': 'multisite'
            };
            select.value = options[templateName] || 'basic';
        }
        
        // Handle form submission
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
            logsDiv.textContent = '馃殌 Starting deployment...\\n';
            
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
                    statusDiv.textContent = \`鉁� Deployment started! ID: \${currentDeploymentId}\`;
                    statusDiv.style.display = 'block';
                    
                    // Start polling for logs
                    startLogPolling(currentDeploymentId);
                    
                    // Clear form
                    document.getElementById('sshKey').value = '';
                } else {
                    throw new Error(data.error);
                }
                
            } catch (error) {
                statusDiv.className = 'status status-error';
                statusDiv.textContent = \`鉂� Error: \${error.message}\`;
                statusDiv.style.display = 'block';
                logsDiv.textContent += \`\\n鉂� \${error.message}\`;
                
            } finally {
                btn.disabled = false;
                btnText.style.display = 'inline';
                btnSpinner.style.display = 'none';
            }
        });
        
        // Poll for deployment status and logs
        function startLogPolling(id) {
            if (logInterval) clearInterval(logInterval);
            
            logInterval = setInterval(async () => {
                try {
                    // Get logs
                    const logsResponse = await fetch(\`/api/logs?id=\${id}\`);
                    const logs = await logsResponse.text();
                    
                    const logsDiv = document.getElementById('logs');
                    if (logs) {
                        logsDiv.textContent = logs;
                        logsDiv.scrollTop = logsDiv.scrollHeight;
                    }
                    
                    // Get status
                    const statusResponse = await fetch(\`/api/status?id=\${id}\`);
                    const status = await statusResponse.json();
                    
                    const statusDiv = document.getElementById('status');
                    
                    if (status.status === 'completed') {
                        clearInterval(logInterval);
                        statusDiv.className = 'status status-success';
                        statusDiv.textContent = '鉁� Deployment completed successfully!';
                        loadRecentDeployments();
                    } else if (status.status === 'failed') {
                        clearInterval(logInterval);
                        statusDiv.className = 'status status-error';
                        statusDiv.textContent = \`鉂� Deployment failed: \${status.error}\`;
                    }
                    
                } catch (error) {
                    console.error('Failed to fetch status:', error);
                }
            }, 2000);
        }
        
        // Load recent deployments
        async function loadRecentDeployments() {
            // In a real implementation, you'd fetch from an API
            // For now, we'll just show the current deployment
            const container = document.getElementById('recentDeployments');
            if (currentDeploymentId) {
                container.innerHTML = \`
                    <div class="deployment-item">
                        <strong>Deployment: \${currentDeploymentId}</strong><br>
                        <small>Started: \${new Date().toLocaleString()}</small><br>
                        <span class="badge badge-warning">In Progress</span>
                    </div>
                \`;
            }
        }
        
        // Initialize
        loadTemplates();
        loadRecentDeployments();
    </script>
</body>
</html>`;
  
  return new Response(html, {
    headers: { 'Content-Type': 'text/html' },
  });
}

// ============================================
// Handle deployment request
// ============================================
async function handleDeploy(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  try {
    const { domain, serverIp, sshPort, sshUser, sshKey, template } = await request.json();
    
    // Validate input
    if (!domain || !serverIp || !sshUser || !sshKey) {
      return new Response(JSON.stringify({ 
        success: false, 
        error: 'Missing required fields' 
      }), { status: 400 });
    }
    
    // Generate unique deployment ID
    const deploymentId = crypto.randomUUID();
    
    // Store deployment info
    const deployment = {
      id: deploymentId,
      domain,
      serverIp,
      sshPort: sshPort || 22,
      sshUser,
      template,
      status: 'pending',
      startTime: new Date().toISOString(),
      logs: ''
    };
    
    deployments.set(deploymentId, deployment);
    logs.set(deploymentId, `[${new Date().toISOString()}] 馃殌 Deployment started for ${domain}\n`);
    
    // Execute deployment in background
    ctx.waitUntil(
      executeDeployment(deploymentId, domain, serverIp, sshPort || 22, sshUser, sshKey, template, env)
    );
    
    return new Response(JSON.stringify({
      success: true,
      deploymentId,
      message: 'Deployment started'
    }), {
      headers: { 'Content-Type': 'application/json' },
    });
    
  } catch (error) {
    return new Response(JSON.stringify({ 
      success: false, 
      error: error.message 
    }), { 
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

// ============================================
// Execute deployment via SSH
// ============================================
async function executeDeployment(
  deploymentId: string,
  domain: string,
  serverIp: string,
  sshPort: number,
  sshUser: string,
  sshKey: string,
  template: string,
  env: Env
) {
  const log = (message: string) => {
    const currentLogs = logs.get(deploymentId) || '';
    logs.set(deploymentId, currentLogs + `[${new Date().toISOString()}] ${message}\n`);
    console.log(`[${deploymentId}] ${message}`);
  };
  
  try {
    log('馃攲 Establishing SSH connection...');
    
    // Create SSH client
    const client = new Client();
    
    await new Promise((resolve, reject) => {
      client.on('ready', () => {
        log('鉁� SSH connection established');
        
        // Build deployment command based on template
        let command = '';
        switch (template) {
          case 'ssl':
            command = `curl -sSL ${env.GITHUB_RAW_URL} | bash && easyinstall domain ${domain} --ssl`;
            break;
          case 'multisite':
            command = `curl -sSL ${env.GITHUB_RAW_URL} | bash && easyinstall panel`;
            break;
          default:
            command = `curl -sSL ${env.GITHUB_RAW_URL} | bash && easyinstall domain ${domain}`;
        }
        
        log(`馃摝 Executing: ${command}`);
        
        client.exec(command, (err, stream) => {
          if (err) {
            reject(err);
            return;
          }
          
          stream.on('close', (code, signal) => {
            log(`鉁� Process finished with code ${code}`);
            client.end();
            
            // Update deployment status
            const deployment = deployments.get(deploymentId);
            if (deployment) {
              deployment.status = code === 0 ? 'completed' : 'failed';
              deployment.endTime = new Date().toISOString();
              deployments.set(deploymentId, deployment);
            }
            
            resolve(true);
          });
          
          stream.on('data', (data) => {
            log(data.toString());
          });
          
          stream.stderr.on('data', (data) => {
            log(`鈿狅笍  ${data.toString()}`);
          });
        });
      });
      
      client.on('error', (err) => {
        log(`鉂� SSH Error: ${err.message}`);
        reject(err);
      });
      
      // Connect
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
    log(`鉂� Deployment failed: ${error.message}`);
    
    const deployment = deployments.get(deploymentId);
    if (deployment) {
      deployment.status = 'failed';
      deployment.error = error.message;
      deployment.endTime = new Date().toISOString();
      deployments.set(deploymentId, deployment);
    }
  }
}

// ============================================
// Handle status request
// ============================================
function handleStatus(deploymentId: string | null): Response {
  if (!deploymentId) {
    return new Response(JSON.stringify({ error: 'Missing deployment ID' }), { status: 400 });
  }
  
  const deployment = deployments.get(deploymentId);
  
  if (!deployment) {
    return new Response(JSON.stringify({ error: 'Deployment not found' }), { status: 404 });
  }
  
  return new Response(JSON.stringify({
    status: deployment.status,
    startTime: deployment.startTime,
    endTime: deployment.endTime,
    error: deployment.error
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
}

// ============================================
// Handle logs request
// ============================================
function handleLogs(deploymentId: string | null): Response {
  if (!deploymentId) {
    return new Response('Missing deployment ID', { status: 400 });
  }
  
  const deploymentLogs = logs.get(deploymentId) || 'No logs found';
  
  return new Response(deploymentLogs, {
    headers: { 'Content-Type': 'text/plain' },
  });
}

// ============================================
// Handle templates request
// ============================================
function handleTemplates(): Response {
  const templates = [
    {
      name: 'WordPress Basic',
      description: 'WordPress with basic configuration and Nginx',
      command: 'easyinstall domain {domain}'
    },
    {
      name: 'WordPress with SSL',
      description: 'WordPress with automatic SSL certificate via Let\'s Encrypt',
      command: 'easyinstall domain {domain} --ssl'
    },
    {
      name: 'Multi-site Setup',
      description: 'Configure server for multiple WordPress sites',
      command: 'easyinstall panel'
    },
    {
      name: 'WordPress + Redis',
      description: 'WordPress with Redis object cache',
      command: 'easyinstall domain {domain} && easyinstall redis'
    },
    {
      name: 'WordPress + CDN',
      description: 'WordPress with Cloudflare CDN integration',
      command: 'easyinstall domain {domain} && easyinstall cdn'
    }
  ];
  
  return new Response(JSON.stringify({ templates }), {
    headers: { 'Content-Type': 'application/json' },
  });
}
