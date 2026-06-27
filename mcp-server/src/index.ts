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
        name: "apply_salt_state",
        description: "執行 Salt 指令進行 HAProxy 部署",
        inputSchema: {
          type: "object",
          properties: {
            target: { type: "string", description: "目標機器，例如 ha-gs-1 或 ha-*" },
            state: { type: "string", description: "要執行的 state，例如 haproxy.ccc-dconfig", default: "haproxy.ccc-dconfig" },
            testMode: { type: "boolean", description: "是否只做 test=True 測試", default: false },
          },
          required: ["target"],
        },
      },
      {
        name: "test_haproxy_in_docker",
        description: "啟動 Docker 沙盒測試 HAProxy 設定檔 (haproxy -c)。會自動掛載本機 Repo 內的 hostmap 與 whitelist 進行驗證。",
        inputSchema: {
          type: "object",
          properties: {
            envDir: { type: "string", description: "環境目錄名稱，例如: ha-std, ha-gs, ha-dev" },
            target: { type: "string", description: "若不提供 cfgContent，會透過 Salt 抓取目標機器的 haproxy.cfg，例如: ha-std-1" },
            cfgContent: { type: "string", description: "自訂的 haproxy.cfg 完整內容 (可選)" }
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

    if (name === "apply_salt_state") {
      const { target, state = "haproxy.ccc-dconfig", testMode = false } = args as any;
      
      if (!/^[a-zA-Z0-9_\-\*]+$/.test(target)) {
        throw new Error("Invalid target format");
      }

      const testFlag = testMode ? " test=True" : "";
      const cmd = `sudo salt '${target}' state.apply ${state}${testFlag}`;
      
      try {
        const { stdout, stderr } = await execAsync(cmd);
        const hasFailed = stdout.includes("Failed:    0") === false && stdout.includes("Failed:");
        
        return {
          isError: hasFailed,
          content: [{ 
            type: "text", 
            text: `Command: ${cmd}\n\nResult:\n${stdout || stderr}` 
          }],
        };
      } catch (error: any) {
        return {
          isError: true,
          content: [{ type: "text", text: `Salt execution failed:\n${error.message}\n${error.stdout}\n${error.stderr}` }],
        };
      }
    }

    if (name === "test_haproxy_in_docker") {
      const { envDir, target, cfgContent } = args as any;
      
      let finalCfgContent = cfgContent;
      
      // 如果沒有傳入自訂 config，透過 Salt 去目標機器抓目前的設定檔
      if (!finalCfgContent && target) {
        if (!/^[a-zA-Z0-9_\-\*]+$/.test(target)) throw new Error("Invalid target format");
        const { stdout } = await execAsync(`sudo salt '${target}' cmd.run 'cat /etc/haproxy/haproxy.cfg'`);
        const lines = stdout.split('\n');
        // Salt cmd.run 會在第一行印出機器名稱，例如 "ha-std-1:"，必須移除
        if (lines[0].includes(':')) lines.shift();
        finalCfgContent = lines.join('\n');
      }

      if (!finalCfgContent) {
        throw new Error("Must provide either cfgContent or a valid target to fetch from.");
      }

      // Hack: 移除設定檔中的 ssl crt 路徑檢查
      // 因為 Docker Sandbox 內沒有掛載實際憑證，保留會導致 `haproxy -c` 報錯
      finalCfgContent = finalCfgContent.replace(/ssl crt \S+/g, "");

      // 建立暫存檔存放 config
      const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "haproxy-sandbox-"));
      const tmpCfgPath = path.join(tmpDir, "haproxy.cfg");
      await fs.writeFile(tmpCfgPath, finalCfgContent, "utf-8");

      // 取得對應環境的 map 與 whitelist 路徑
      const localEnvDir = path.join(ACTUAL_REPO_ROOT, "five-gemmis-ha/haproxy/config", envDir);
      const hostmapDir = path.join(localEnvDir, "hostmap");
      const whitelistDir = path.join(localEnvDir, "whitelist");

      // 組合 Docker 指令，將設定檔與目錄掛載進去驗證
      const dockerCmd = `docker run --rm -v "${tmpCfgPath}:/etc/haproxy/haproxy.cfg:ro" -v "${hostmapDir}:/etc/haproxy/hostmap:ro" -v "${whitelistDir}:/etc/haproxy/whitelist:ro" haproxy:alpine haproxy -c -f /etc/haproxy/haproxy.cfg`;

      try {
        const { stdout, stderr } = await execAsync(dockerCmd);
        return {
          content: [{ type: "text", text: `✅ Sandbox Validation Passed!\n\n${stdout || stderr}` }]
        };
      } catch (error: any) {
        return {
          isError: true,
          content: [{ type: "text", text: `❌ Sandbox Validation Failed:\n${error.stderr || error.stdout || error.message}` }]
        };
      } finally {
        // 清理暫存檔
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