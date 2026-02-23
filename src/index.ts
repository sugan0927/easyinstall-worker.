cat > src/index.ts << 'EOF'
import { Hono } from 'hono';

const app = new Hono();

// GitHub raw URL से script fetch करें
const SCRIPT_URL = 'https://raw.githubusercontent.com/sugan09/easyinstall-worker/main/easyinstall.sh';

app.get('/script', async (c) => {
  try {
    // GitHub से script fetch करें
    const response = await fetch(SCRIPT_URL);
    
    if (!response.ok) {
      return new Response(`Failed to fetch script: ${response.status}`, { status: 500 });
    }
    
    const scriptContent = await response.text();
    
    return new Response(scriptContent, {
      headers: {
        'Content-Type': 'text/plain',
        'Content-Disposition': 'attachment; filename="easyinstall.sh"'
      }
    });
  } catch (error) {
    return new Response(`Error: ${error.message}`, { status: 500 });
  }
});

// GitHub से script fetch करके दिखाएं
app.get('/script/view', async (c) => {
  try {
    const response = await fetch(SCRIPT_URL);
    const scriptContent = await response.text();
    
    const lines = scriptContent.split('\n');
    const numberedContent = lines.map((line, index) => 
      `${(index + 1).toString().padStart(4, ' ')} | ${line}`
    ).join('\n');
    
    return new Response(numberedContent, {
      headers: { 'Content-Type': 'text/plain' }
    });
  } catch (error) {
    return new Response(`Error: ${error.message}`, { status: 500 });
  }
});

// Main page
app.get('/', (c) => {
  const baseUrl = new URL(c.req.url).origin;
  
  return c.html(`
    <!DOCTYPE html>
    <html>
    <head>
        <title>EasyInstall - VPS Script Installer</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
                background: linear-gradient(135deg, #0b0b1f 0%, #1a1a3a 100%);
                min-height: 100vh;
                color: white;
            }
            .container {
                max-width: 1000px;
                margin: 0 auto;
                padding: 40px 20px;
            }
            .header {
                text-align: center;
                margin-bottom: 50px;
            }
            .header h1 {
                font-size: 3em;
                margin-bottom: 10px;
                background: linear-gradient(45deg, #00d2ff, #3a7bd5);
                -webkit-background-clip: text;
                -webkit-text-fill-color: transparent;
            }
            .header p {
                color: #8899aa;
                font-size: 1.2em;
            }
            .card {
                background: rgba(255, 255, 255, 0.05);
                border: 1px solid rgba(255, 255, 255, 0.1);
                border-radius: 20px;
                padding: 30px;
                margin-bottom: 30px;
                backdrop-filter: blur(10px);
            }
            .card h2 {
                margin-bottom: 20px;
                color: #00d2ff;
            }
            .command-box {
                background: #0a0a1f;
                border-radius: 12px;
                padding: 20px;
                margin: 15px 0;
                position: relative;
                font-family: 'Courier New', monospace;
                border-left: 4px solid #00d2ff;
            }
            .command {
                color: #00ff9d;
                word-break: break-all;
                font-size: 1.1em;
            }
            .copy-btn {
                position: absolute;
                top: 10px;
                right: 10px;
                background: #3a7bd5;
                color: white;
                border: none;
                border-radius: 6px;
                padding: 8px 15px;
                cursor: pointer;
                font-size: 0.9em;
                transition: all 0.3s;
            }
            .copy-btn:hover {
                background: #00d2ff;
                transform: scale(1.05);
            }
            .note {
                background: rgba(255, 193, 7, 0.1);
                border-left: 4px solid #ffc107;
                padding: 15px;
                border-radius: 8px;
                margin: 20px 0;
                color: #ffd966;
            }
            .button-group {
                display: flex;
                gap: 15px;
                flex-wrap: wrap;
                margin-top: 20px;
            }
            .button {
                background: linear-gradient(45deg, #00d2ff, #3a7bd5);
                color: white;
                text-decoration: none;
                padding: 12px 25px;
                border-radius: 8px;
                font-weight: bold;
                transition: transform 0.3s;
                border: none;
                cursor: pointer;
            }
            .button:hover {
                transform: translateY(-2px);
            }
            .feature-grid {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
                gap: 20px;
                margin-top: 30px;
            }
            .feature {
                text-align: center;
                padding: 20px;
            }
            .feature h3 {
                margin: 15px 0;
                color: #00d2ff;
            }
            .feature p {
                color: #8899aa;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>🚀 EasyInstall</h1>
                <p>One command to install anything on your VPS</p>
            </div>
            
            <div class="card">
                <h2>📦 Quick Install</h2>
                <p>Run this command on your VPS:</p>
                
                <div class="command-box">
                    <div class="command">curl -sL ${baseUrl}/script | bash</div>
                    <button class="copy-btn" onclick="copyCommand('curl -sL ${baseUrl}/script | bash')">Copy</button>
                </div>
                
                <div class="note">
                    ⚡ This will download and run the installation script on your VPS immediately.
                </div>
            </div>
            
            <div class="card">
                <h2>📥 Download Script</h2>
                <p>First download, then run:</p>
                
                <div class="command-box">
                    <div class="command">wget -O easyinstall.sh ${baseUrl}/script</div>
                    <button class="copy-btn" onclick="copyCommand('wget -O easyinstall.sh ${baseUrl}/script')">Copy</button>
                </div>
                
                <div class="command-box">
                    <div class="command">chmod +x easyinstall.sh && ./easyinstall.sh</div>
                    <button class="copy-btn" onclick="copyCommand('chmod +x easyinstall.sh && ./easyinstall.sh')">Copy</button>
                </div>
            </div>
            
            <div class="card">
                <h2>📦 Install Specific Package</h2>
                <p>Pass package name as argument:</p>
                
                <div class="command-box">
                    <div class="command">curl -sL ${baseUrl}/script | bash -s nginx</div>
                    <button class="copy-btn" onclick="copyCommand('curl -sL ${baseUrl}/script | bash -s nginx')">Copy</button>
                </div>
                
                <div class="command-box">
                    <div class="command">curl -sL ${baseUrl}/script | bash -s nodejs mysql redis</div>
                    <button class="copy-btn" onclick="copyCommand('curl -sL ${baseUrl}/script | bash -s nodejs mysql redis')">Copy</button>
                </div>
            </div>
            
            <div class="card">
                <h2>🎯 How it works</h2>
                <div class="feature-grid">
                    <div class="feature">
                        <div style="font-size: 3em;">1️⃣</div>
                        <h3>Fetch</h3>
                        <p>Cloudflare Worker serves the script from GitHub</p>
                    </div>
                    <div class="feature">
                        <div style="font-size: 3em;">2️⃣</div>
                        <h3>Run</h3>
                        <p>Your VPS downloads and executes the script</p>
                    </div>
                    <div class="feature">
                        <div style="font-size: 3em;">3️⃣</div>
                        <h3>Install</h3>
                        <p>Script installs packages using your VPS's package manager</p>
                    </div>
                </div>
            </div>
            
            <div class="button-group">
                <a href="/script" class="button" download>📄 Download Script</a>
                <a href="/script/view" class="button">👁️ View Script</a>
                <a href="https://github.com/yourusername/easyinstall" class="button">⭐ GitHub</a>
            </div>
        </div>
        
        <script>
            function copyCommand(cmd) {
                navigator.clipboard.writeText(cmd).then(() => {
                    alert('✅ Command copied to clipboard!');
                });
            }
        </script>
    </body>
    </html>
  `);
});

// API endpoint for JSON response
app.get('/api/script', async (c) => {
  try {
    const response = await fetch(SCRIPT_URL);
    const scriptContent = await response.text();
    
    return c.json({
      success: true,
      script_url: SCRIPT_URL,
      script_content: scriptContent,
      commands: {
        direct: `curl -sL ${c.req.url.replace('/api/script', '')}/script | bash`,
        download: `wget -O easyinstall.sh ${c.req.url.replace('/api/script', '')}/script`
      }
    });
  } catch (error) {
    return c.json({ success: false, error: error.message }, 500);
  }
});

export default app;
EOF
