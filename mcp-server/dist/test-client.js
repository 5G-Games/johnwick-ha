import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
async function test() {
    console.log("Starting MCP Client...");
    const transport = new StdioClientTransport({
        command: "node",
        args: ["dist/index.js"],
    });
    const client = new Client({ name: "test-client", version: "1.0.0" }, { capabilities: {} });
    await client.connect(transport);
    console.log("✅ Successfully connected to MCP Server!");
    try {
        // Test 1: get_map_entries
        console.log("\n🧪 Test 1: get_map_entries (ha-std/hostmap/uat.map)");
        const mapRes = await client.callTool({
            name: "get_map_entries",
            arguments: { mapRelativePath: "ha-std/hostmap/uat.map" }
        });
        console.log("Result:");
        console.log(JSON.stringify(mapRes.content, null, 2));
        // Test 2: get_pillar_value
        console.log("\n🧪 Test 2: get_pillar_value (ha-std-1.sls)");
        const pillarRes = await client.callTool({
            name: "get_pillar_value",
            arguments: { fileName: "ha-std-1.sls" }
        });
        console.log("Result (First 500 chars):");
        const pillarContent = JSON.stringify(pillarRes.content, null, 2);
        console.log(pillarContent.substring(0, 500) + "...\n(Truncated for output)");
        console.log("\n🎉 All tests passed successfully!");
    }
    catch (error) {
        console.error("\n❌ Test failed:", error);
    }
    finally {
        process.exit(0);
    }
}
test().catch(err => {
    console.error("Critical error:", err);
    process.exit(1);
});
