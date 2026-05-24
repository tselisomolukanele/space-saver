CREATE TABLE IF NOT EXISTS album (
  hash TEXT NOT NULL,
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (hash, key)
);
