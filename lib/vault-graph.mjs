import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
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
const insertFile = db.prepare('INSERT INTO files (path,content_hash,language,size,modified_at,indexed_at,node_count,errors) VALUES (?,?,?,?,?,?,?,NULL)');
const insertNode = db.prepare('INSERT INTO nodes (id,kind,name,qualified_name,file_path,language,start_line,end_line,start_column,end_column,docstring,signature,visibility,is_exported,is_async,is_static,is_abstract,decorators,type_parameters,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)');
const insertEdge = db.prepare('INSERT INTO edges (source,target,kind,metadata,line,col,provenance) VALUES (?,?,?,?,?,?,?)');
const rels = [...new Set(data.nodes.filter(n=>n.kind==='file').map(n=>n.path))].sort();
for (const rel of rels) {
  const full = path.join(vault, rel);
  const content = fs.readFileSync(full, 'utf8');
  const stat = fs.statSync(full);
  const hash = crypto.createHash('sha256').update(content).digest('hex');
  const nodesFor = data.nodes.filter(n=>n.path===rel);
  insertFile.run(rel, hash, 'markdown', stat.size, stat.mtimeMs, now, nodesFor.length);
}
const kindMap = { file:'module', heading:'function', concept:'class', tag:'variable', repo:'class' };
for (const n of data.nodes) {
  insertNode.run(n.id, kindMap[n.kind]||'class', n.label, n.id, n.path||'', 'markdown', n.line||1, n.line||1, 1, 1, null, 'vault:'+n.kind, null, 0,0,0,0,null,null,now);
}
for (const e of data.edges) {
  try { insertEdge.run(e.s, e.t, e.kind, JSON.stringify({}), e.line||1, 1, 'vault'); } catch(_) {}
}
for (const rel of rels) {
  const c = db.prepare('SELECT COUNT(*) AS n FROM nodes WHERE file_path=?').get(rel).n;
  db.prepare('UPDATE files SET node_count=? WHERE path=?').run(c, rel);
}
db.exec('COMMIT');
console.log(`Loaded ${data.nodes.length} nodes, ${data.edges.length} edges, ${rels.length} files.`);
db.close();
