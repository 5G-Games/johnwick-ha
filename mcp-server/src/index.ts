import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import * as fs from "fs/promises";
import * as path from "path";
import { exec } from "child_process";
import { promisify } from "util";
import * as yaml from "yaml";
import * as os from "os";
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const execAsync = promisify(exec);

// 設定基礎路徑 (依據當前專案結構)
const REPO_ROOT = path.resolve(process.cwd(), ".."); // 當用 Inspector 跑時，cwd 可能是 johnwick-ha 或 mcp-server
// 我們改用動態尋找 johnwick-ha 的方式，確保路徑正確
const getRepoRoot = () => {
  const cwd = process.cwd();
  return cwd.endsWith('johnwick-ha') ? cwd : path.resolve(cwd, '..');
};

const ACTUAL_REPO_ROOT = getRepoRoot();
const HAPROXY_MAP_DIR = path.join(ACTUAL_REPO_ROOT, "five-gemmis-ha/haproxy/config");
const PILLAR_DIR = path.join(ACTUAL_REPO_ROOT, "five-gemmis-pillar/server");

const server = new Server(
  {
    name: "haproxy-salt-manager",
    version: "2.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "get_map_entries",
        description: "讀取指定的 HAProxy map 檔案內容 (例如: ha-std/hostmap/uat.map)，並解析成 Key-Value 列表",
        inputSchema: {
          type: "object",
          properties: {
            mapRelativePath: {
              type: "string",
              description: "Map 檔案相對路徑，例如: ha-std/hostmap/uat.map",
            },
          },
          required: ["mapRelativePath"],
        },
      },
      {
        name: "set_map_entry",
        description: "在指定的 HAProxy map 檔案中新增或更新一筆規則 (domain -> backend)",
        inputSchema: {
          type: "object",
          properties: {
            mapRelativePath: { type: "string", description: "例如: ha-std/hostmap/uat.map" },
            domain: { type: "string", description: "來源網域，例如: api.5gg.win" },
            backend: { type: "string", description: "目標 backend 名稱" },
          },
          required: ["mapRelativePath", "domain", "backend"],
        },
      },
      {
        name: "get_pillar_value",
        description: "讀取 Salt Pillar (YAML) 中的設定",
        inputSchema: {
          type: "object",
          properties: {
            fileName: { type: "string", description: "Pillar 檔名，例如 ha-gs-1.sls" },
          },
          required: ["fileName"],
        },
      },
      {
        name: "update_pillar_value",
        description: "安全地修改 Salt Pillar (YAML) 中的設定",
        inputSchema: {
          type: "object",
          properties: {
            fileName: { type: "string", description: "Pillar 檔名，例如 ha-gs-1.sls" },
            path: { type: "string", description: "要修改的 YAML 路徑，以點分隔，例如 server.haproxy.promexporter" },
            value: { type: "string", description: "新的值 (字串、數字或布林值，將自動轉型)" },
          },
          required: ["fileName", "path", "value"],
        },
      },
      {
        name: "test_haproxy_in_docker",
        description: "本地全模擬：自動讀取 Pillar 與 Jinja 模板，渲染出 HAProxy config 後放進 Docker Sandbox 驗證語法。",
        inputSchema: {
          type: "object",
          properties: {
            envDir: { type: "string", description: "環境名稱，例如: ha-std, ha-gs, ha-dev" }
          },
          required: ["envDir"]
        },
      },
      {
        name: "verify_all_domain_routes",
        description: "進階路由驗證：讀取 hostmap 內所有 domain，啟動 HAProxy Docker，並對每個 domain 發送真實 HTTP 請求，驗證是否路由至正確的 Backend。",
        inputSchema: {
          type: "object",
          properties: {
            envDir: { type: "string", description: "環境名稱，例如: ha-std, ha-gs, ha-dev" }
          },
          required: ["envDir"]
        },
      },
    ],
  };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    if (name === "get_map_entries") {
      const { mapRelativePath } = args as { mapRelativePath: string };
      // 防禦路徑穿越
      const safePath = path.normalize(mapRelativePath).replace(/^(\.\.(\/|\\|$))+/, '');
      const filePath = path.join(HAPROXY_MAP_DIR, safePath);
      
      const content = await fs.readFile(filePath, "utf-8");
      const entries = content
        .split("\n")
        .map(line => line.trim())
        .filter(line => line && !line.startsWith("#"))
        .map(line => {
          const [domain, backend] = line.split(/\s+/);
          return { domain, backend };
        });

      return {
        content: [{ type: "text", text: JSON.stringify(entries, null, 2) }],
      };
    }

    if (name === "set_map_entry") {
      const { mapRelativePath, domain, backend } = args as {
        mapRelativePath: string;
        domain: string;
        backend: string;
      };
      
      const safePath = path.normalize(mapRelativePath).replace(/^(\.\.(\/|\\|$))+/, '');
      const filePath = path.join(HAPROXY_MAP_DIR, safePath);
      let content = await fs.readFile(filePath, "utf-8").catch(() => "");
      
      const lines = content.split("\n");
      let updated = false;

      const newLines = lines.map(line => {
        if (line.trim().startsWith(domain + " ") || line.trim().startsWith(domain + "\t")) {
          updated = true;
          return `${domain} ${backend}`;
        }
        return line;
      });

      if (!updated) {
        newLines.push(`${domain} ${backend}`);
      }

      await fs.writeFile(filePath, newLines.join("\n").trim() + "\n", "utf-8");

      return {
        content: [{ type: "text", text: `Successfully set ${domain} -> ${backend} in ${mapRelativePath}` }],
      };
    }

    if (name === "get_pillar_value") {
      const { fileName } = args as { fileName: string };
      const safeFileName = path.basename(fileName);
      const filePath = path.join(PILLAR_DIR, safeFileName);
      const content = await fs.readFile(filePath, "utf-8");
      
      const parsed = yaml.parse(content);
      return {
        content: [{ type: "text", text: JSON.stringify(parsed, null, 2) }],
      };
    }

    if (name === "update_pillar_value") {
      const { fileName, path: yamlPath, value } = args as any;
      const safeFileName = path.basename(fileName);
      const filePath = path.join(PILLAR_DIR, safeFileName);
      const content = await fs.readFile(filePath, "utf-8");

      const doc = yaml.parseDocument(content);
      const pathArray = yamlPath.split(".");
      
      // 嘗試轉型為 boolean 或 number，否則保持字串
      let parsedValue: any = value;
      if (value === "true") parsedValue = true;
      else if (value === "false") parsedValue = false;
      else if (!isNaN(Number(value))) parsedValue = Number(value);

      doc.setIn(pathArray, parsedValue);
      
      await fs.writeFile(filePath, doc.toString(), "utf-8");

      return {
        content: [{ type: "text", text: `Successfully updated ${yamlPath} to ${parsedValue} in ${fileName}` }],
      };
    }

    if (name === "test_haproxy_in_docker") {
      const { envDir } = args as any;
      
      const pillarPath = path.join(ACTUAL_REPO_ROOT, `five-gemmis-pillar/server/${envDir}-1.sls`);
      const suffix = envDir.replace("ha-", "");
      const templatePath = path.join(ACTUAL_REPO_ROOT, `five-gemmis-ha/haproxy/config/${envDir}/haproxy.${suffix}.jinja`);
      // 因為編譯後的檔案在 dist 內，而 Python 腳本在 src 內，所以往上一層找
      const renderScript = path.join(__dirname, "../src/utils/render.py");

      let renderedConfig = "";
      try {
        const { stdout } = await execAsync(`python3 "${renderScript}" "${pillarPath}" "${templatePath}" "${envDir}-1"`);
        renderedConfig = stdout;
      } catch (err: any) {
        return {
          isError: true,
          content: [{ type: "text", text: `❌ 本地渲染 Jinja 失敗：\n${err.stderr || err.message}` }]
        };
      }

      // 建立暫存檔存放 config
      const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "haproxy-sandbox-"));
      const tmpCfgPath = path.join(tmpDir, "haproxy.cfg");
      await fs.writeFile(tmpCfgPath, renderedConfig, "utf-8");

      // 取得對應環境的 map 與 whitelist 路徑
      const localEnvDir = path.join(ACTUAL_REPO_ROOT, "five-gemmis-ha/haproxy/config", envDir);
      const hostmapDir = path.join(localEnvDir, "hostmap");
      const whitelistDir = path.join(localEnvDir, "whitelist");

      // 組合 Docker 指令，將設定檔與目錄掛載進去驗證 (指定使用 3.2 版與線上環境對齊)
      const dockerCmd = `docker run --rm -v "${tmpCfgPath}:/etc/haproxy/haproxy.cfg:ro" -v "${hostmapDir}:/etc/haproxy/hostmap:ro" -v "${whitelistDir}:/etc/haproxy/whitelist:ro" haproxy:3.2-alpine haproxy -c -f /etc/haproxy/haproxy.cfg`;

      try {
        const { stdout, stderr } = await execAsync(dockerCmd);
        const preview = renderedConfig.split('\n').slice(0, 15).join('\n');
        return {
          content: [{ type: "text", text: `✅ 本地渲染與 Sandbox 驗證成功！\n\n${stdout || stderr}\n\n[產生的 Config 前 15 行預覽]\n${preview}...` }]
        };
      } catch (error: any) {
        return {
          isError: true,
          content: [{ type: "text", text: `❌ Sandbox 驗證失敗：\n${error.stderr || error.stdout || error.message}` }]
        };
      } finally {
        // 清理暫存檔
        await fs.rm(tmpDir, { recursive: true, force: true }).catch(() => {});
      }
    }

    if (name === "verify_all_domain_routes") {
      const { envDir } = args as any;
      
      const pillarPath = path.join(ACTUAL_REPO_ROOT, `five-gemmis-pillar/server/${envDir}-1.sls`);
      const suffix = envDir.replace("ha-", "");
      const templatePath = path.join(ACTUAL_REPO_ROOT, `five-gemmis-ha/haproxy/config/${envDir}/haproxy.${suffix}.jinja`);
      const renderScript = path.join(__dirname, "../src/utils/render.py");

      let renderedConfig = "";
      try {
        const { stdout } = await execAsync(`python3 "${renderScript}" "${pillarPath}" "${templatePath}" "${envDir}-1"`);
        renderedConfig = stdout;
      } catch (err: any) {
        return { isError: true, content: [{ type: "text", text: `❌ 本地渲染 Jinja 失敗：\n${err.stderr || err.message}` }] };
      }

      // 為了測試路由，我們需要開啟 HAProxy stdout debug log
      renderedConfig = renderedConfig.replace(
        "global\n", 
        "global\n    log stdout format raw local0 debug\n"
      );

      const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "haproxy-sandbox-"));
      const tmpCfgPath = path.join(tmpDir, "haproxy.cfg");
      await fs.writeFile(tmpCfgPath, renderedConfig, "utf-8");

      const localEnvDir = path.join(ACTUAL_REPO_ROOT, "five-gemmis-ha/haproxy/config", envDir);
      const hostmapDir = path.join(localEnvDir, "hostmap");
      const whitelistDir = path.join(localEnvDir, "whitelist");

      // 背景啟動 HAProxy (-d daemon flag 移除，使用 docker run -d)
      const containerName = `haproxy-route-test-${Date.now()}`;
      const port80 = Math.floor(Math.random() * 10000) + 20000; // 隨機分配 20000~29999
      const port443 = port80 + 1;
      const dockerCmd = `docker run -d --name ${containerName} -p ${port80}:80 -p ${port443}:443 -v "${tmpCfgPath}:/etc/haproxy/haproxy.cfg:ro" -v "${hostmapDir}:/etc/haproxy/hostmap:ro" -v "${whitelistDir}:/etc/haproxy/whitelist:ro" haproxy:3.2-alpine haproxy -f /etc/haproxy/haproxy.cfg`;

      try {
        await execAsync(dockerCmd);
        await new Promise(r => setTimeout(r, 2000)); // 等待啟動

        // 讀取 map 檔案取得所有要測試的 domains
        const mapFiles = await fs.readdir(hostmapDir);
        const testCases: { mapFile: string; domain: string; expectedBackend: string; uniquePath?: string }[] = [];
        for (const mapFile of mapFiles) {
            if (!mapFile.endsWith(".map")) continue;
            const content = await fs.readFile(path.join(hostmapDir, mapFile), "utf-8");
            for (const line of content.split("\n")) {
                const [domain, expectedBackend] = line.trim().split(/\s+/);
                if (domain && expectedBackend && !domain.startsWith("#")) {
                    testCases.push({ mapFile, domain, expectedBackend });
                }
            }
        }

        // 對每個 domain 送出 curl 請求 (包含 X-Forwarded-For 模擬允許的 Office IP)
        for (const tc of testCases) {
            const uniquePath = `/?test=${tc.domain}`;
            tc.uniquePath = uniquePath;
            try {
                await execAsync(`curl -s -H "Host: ${tc.domain}" -H "X-Forwarded-For: 125.228.105.246" "http://localhost:${port80}${uniquePath}"`);
            } catch (e) {}
        }

        await new Promise(r => setTimeout(r, 1000)); // 等待日誌寫入
        const { stdout: dockerLogs } = await execAsync(`docker logs ${containerName}`);
        
        // 解析日誌找出實際路由的 Backend
        const results = [];
        for (const tc of testCases) {
            const logLine = dockerLogs.split("\n").find((l: string) => l.includes(`GET ${tc.uniquePath}`));
            if (logLine) {
                // Regex 提取 <frontend>/<backend>/<server> 格式中的 backend
                const match = logLine.match(/\s(\w+)\/([^\/]+)\/<NOSRV>/);
                if (match) {
                    const actualBackend = match[2];
                    results.push({ ...tc, actualBackend, passed: actualBackend === tc.expectedBackend });
                } else {
                    results.push({ ...tc, actualBackend: "unknown", passed: false });
                }
            } else {
                results.push({ ...tc, actualBackend: "no log found", passed: false });
            }
        }

        const passedCount = results.filter((r: any) => r.passed).length;
        const failedCases = results.filter((r: any) => !r.passed);

        // 解析 Backend Servers
        const backendServers: Record<string, string[]> = {};
        let currentBackend: string | null = null;
        for (const line of renderedConfig.split('\n')) {
            const match = line.match(/^backend\s+(\S+)/);
            if (match) {
                currentBackend = match[1];
                backendServers[currentBackend] = [];
            } else if (currentBackend && line.trim().startsWith('server ')) {
                backendServers[currentBackend].push(line.trim());
            } else if (line.match(/^(frontend|listen|global|defaults)/)) {
                currentBackend = null;
            }
        }

        // 解析 Map Rules
        const mapRules: Record<string, string> = {};
        for (const line of renderedConfig.split('\n')) {
            if (line.includes('use_backend') && line.includes('map_sub')) {
                const mapMatch = line.match(/hostmap\/([a-zA-Z0-9_.-]+\.map)/);
                if (mapMatch) {
                    mapRules[mapMatch[1]] = line.trim();
                }
            }
        }

        let report = `✅ 路由驗證完成！共測試了 ${testCases.length} 個 Domains，通過 ${passedCount} 個。\n\n`;
        
        report += `### 🔬 測試與追蹤細節\n`;
        report += `- **驗證方式**: 啟動 HAProxy Sandbox，對每個 Domain 發送帶有 \`Host: <domain>\` 與 \`X-Forwarded-For: 125.228.105.246\` 的真實請求，並分析日誌確認路由。\n`;
        report += `- **追蹤鏈路**: Domain ➡️ Map 檔案 ➡️ HAProxy 規則 ➡️ Backend ➡️ Server 與 Port\n\n`;

        if (failedCases.length > 0) {
            report += `### ❌ 失敗的 Domains:\n`;
            for (const f of failedCases) {
                report += `- **${f.domain}**: 預期 \`${f.expectedBackend}\`，實際路由至 \`${f.actualBackend}\`\n`;
            }
            report += `\n`;
        }

        report += `### 📊 完整路由對應表\n\n`;

        for (const r of results) {
            const rule = mapRules[r.mapFile] || 'Rule not found';
            const servers = backendServers[r.actualBackend] ? backendServers[r.actualBackend].join('\n  ') : 'No server found';
            const status = r.passed ? '✅ Pass' : '❌ Fail';
            
            report += `#### Domain: \`${r.domain}\` ${status}\n`;
            report += `- **來源 Map**: \`${r.mapFile}\`\n`;
            report += `- **匹配規則**: \`${rule}\`\n`;
            report += `- **實際 Backend**: \`${r.actualBackend}\`\n`;
            report += `- **指向 Server & Port**:\n  \`\`\`\n  ${servers}\n  \`\`\`\n`;
            report += `---\n\n`;
        }

        return { content: [{ type: "text", text: report }] };
      } catch (error: any) {
        return { isError: true, content: [{ type: "text", text: `❌ 路由測試過程發生錯誤：\n${error.message}` }] };
      } finally {
        await execAsync(`docker rm -f ${containerName}`).catch(() => {});
        await fs.rm(tmpDir, { recursive: true, force: true }).catch(() => {});
      }
    }

    throw new Error(`Tool not found: ${name}`);
  } catch (error: any) {
    return {
      isError: true,
      content: [{ type: "text", text: `Error executing ${name}: ${error.message}` }],
    };
  }
});

async function run() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("HAProxy Salt MCP Server running on stdio");
}

run().catch(console.error);