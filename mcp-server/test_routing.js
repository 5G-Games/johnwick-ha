import { exec } from "child_process";
import { promisify } from "util";
import * as path from "path";
import * as fs from "fs/promises";
import * as os from "os";

const execAsync = promisify(exec);

async function test() {
    const envDir = "ha-std";
    const REPO_ROOT = "/Users/feir_huang/5g_data/Github/johnwick-ha";
    const pillarPath = path.join(REPO_ROOT, `five-gemmis-pillar/server/${envDir}-1.sls`);
    const suffix = envDir.replace("ha-", "");
    const templatePath = path.join(REPO_ROOT, `five-gemmis-ha/haproxy/config/${envDir}/haproxy.${suffix}.jinja`);
    const renderScript = path.join(REPO_ROOT, "mcp-server/src/utils/render.py");

    let renderedConfig = "";
    const { stdout } = await execAsync(`python3 "${renderScript}" "${pillarPath}" "${templatePath}" "${envDir}-1"`);
    renderedConfig = stdout;

    renderedConfig = renderedConfig.replace(
        "global\n", 
        "global\n    log stdout format raw local0 debug\n"
    );

    const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "haproxy-sandbox-"));
    const tmpCfgPath = path.join(tmpDir, "haproxy.cfg");
    await fs.writeFile(tmpCfgPath, renderedConfig, "utf-8");

    const localEnvDir = path.join(REPO_ROOT, "five-gemmis-ha/haproxy/config", envDir);
    const hostmapDir = path.join(localEnvDir, "hostmap");
    const whitelistDir = path.join(localEnvDir, "whitelist");

    const dockerCmd = `docker run -d --name haproxy-test-route -p 8080:80 -p 8443:443 -v "${tmpCfgPath}:/etc/haproxy/haproxy.cfg:ro" -v "${hostmapDir}:/etc/haproxy/hostmap:ro" -v "${whitelistDir}:/etc/haproxy/whitelist:ro" haproxy:3.2-alpine haproxy -f /etc/haproxy/haproxy.cfg`;
    
    console.log("Starting container...");
    await execAsync("docker rm -f haproxy-test-route").catch(() => {});
    await execAsync(dockerCmd);

    await new Promise(r => setTimeout(r, 2000));
    
    // Read map files
    const mapFiles = await fs.readdir(hostmapDir);
    const testCases = [];
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

    console.log(`Found ${testCases.length} domains to test.`);
    
    // We send curl for each domain
    for (const tc of testCases) {
        // Send a unique path so we can match it in logs
        const uniquePath = `/?test=${tc.domain}`;
        tc.uniquePath = uniquePath;
        try {
            await execAsync(`curl -s -H "Host: ${tc.domain}" -H "X-Forwarded-For: 125.228.105.246" "http://localhost:8080${uniquePath}"`);
        } catch (e) {}
    }

    // Give it a sec to write logs
    await new Promise(r => setTimeout(r, 1000));

    const { stdout: dockerLogs } = await execAsync("docker logs haproxy-test-route");
    
    // Parse logs to find backend
    const results = [];
    for (const tc of testCases) {
        // Look for log line containing the unique path
        // e.g. fe_http_gs_in/backend_name/... "GET /?test=api-dev.5gg.io HTTP/1.1"
        const logLine = dockerLogs.split("\n").find(l => l.includes(`GET ${tc.uniquePath}`));
        if (logLine) {
            const match = logLine.match(/\s(\w+)\/([^\/]+)\/<NOSRV>/);
            if (match) {
                const actualBackend = match[2];
                results.push({ ...tc, actualBackend, passed: actualBackend === tc.expectedBackend });
            } else {
                results.push({ ...tc, actualBackend: "unknown (regex failed)", passed: false, log: logLine });
            }
        } else {
            results.push({ ...tc, actualBackend: "no log found", passed: false });
        }
    }

    const passedCount = results.filter(r => r.passed).length;
    console.log(`Test Result: ${passedCount} / ${testCases.length} passed.`);
    
    // Print all results for debug
    console.table(results.map(r => ({ domain: r.domain, expected: r.expectedBackend, actual: r.actualBackend, passed: r.passed })));

    await execAsync("docker rm -f haproxy-test-route");
}
test();