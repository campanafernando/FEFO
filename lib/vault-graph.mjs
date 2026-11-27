// Loads FEFO's vault-graph.json into CodeGraph's SQLite schema (run with CodeGraph's bundled node).
// No `files` rows on purpose: CodeGraph's connect-time catch-up walks `files` and deletes rows for
// files it cannot parse (Markdown), which would wipe the vault graph on the first MCP query.
import fs from 'fs';
import path from 'path';
import { DatabaseSync } from 'node:sqlite';
const vault = process.argv[2];
const jsonPath = path.join(vault, '.codegraph', 'vault-graph.json');
const dbPath = path.join(vault, '.codegraph', 'codegraph.db');
if (!fs.existsSync(dbPath)) { console.error('DB missing; run codegraph init first'); process.exit(1); }
const data = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
const db = new DatabaseSync(dbPath);
const now = Date.now();
db.exec('BEGIN');
db.prepare('DELETE FROM edges').run();
db.prepare('DELETE FROM nodes').run();
db.prepare('DELETE FROM files').run();
db.prepare('DELETE FROM unresolved_refs').run();
const insertNode = db.prepare('INSERT INTO nodes (id,kind,name,qualified_name,file_path,language,start_line,end_line,start_column,end_column,docstring,signature,visibility,is_exported,is_async,is_static,is_abstract,decorators,type_parameters,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)');
const insertEdge = db.prepare('INSERT INTO edges (source,target,kind,metadata,line,col,provenance) VALUES (?,?,?,?,?,?,?)');
const kindMap = { file:'module', heading:'function', concept:'class', tag:'variable', repo:'class' };
for (const n of data.nodes) {
  insertNode.run(n.id, kindMap[n.kind]||'class', n.label, n.id, n.path||'', 'markdown', n.line||1, n.line||1, 1, 1, null, 'vault:'+n.kind, null, 0,0,0,0,null,null,now);
}
for (const e of data.edges) {
  try { insertEdge.run(e.s, e.t, e.kind, JSON.stringify({}), e.line||1, 1, 'vault'); } catch(_) {}
}
db.exec('COMMIT');
const notes = new Set(data.nodes.filter(n => n.kind === 'file').map(n => n.path)).size;
console.log(`Loaded ${data.nodes.length} nodes, ${data.edges.length} edges from ${notes} notes.`);
db.close();
