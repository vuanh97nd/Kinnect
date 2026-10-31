CREATE TABLE chat_import_runs (
 id TEXT PRIMARY KEY,
 source_sha256 TEXT NOT NULL,
 created_at INTEGER NOT NULL,
 state TEXT NOT NULL CHECK(state IN ('imported','verified')),
 expected_rows INTEGER NOT NULL
);
CREATE TABLE chat_import_rows (
 run_id TEXT NOT NULL REFERENCES chat_import_runs(id),
 table_name TEXT NOT NULL,
 row_number INTEGER NOT NULL,
 payload TEXT NOT NULL CHECK(json_valid(payload)),
 sha256 TEXT NOT NULL,
 PRIMARY KEY(run_id,table_name,row_number)
);
