-- 3D City Database - The Open Source CityGML Database
-- http://www.3dcitydb.org/
-- 
-- Copyright 2013 - 2018
-- Chair of Geoinformatics
-- Technical University of Munich, Germany
-- https://www.gis.bgu.tum.de/
-- 
-- The 3D City Database is jointly developed with the following
-- cooperation partners:
-- 
-- virtualcitySYSTEMS GmbH, Berlin <http://www.virtualcitysystems.de/>
-- M.O.S.S. Computer Grafik Systeme GmbH, Taufkirchen <http://www.moss.de/>
-- 
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
-- 
--     http://www.apache.org/licenses/LICENSE-2.0
--     
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

/*****************************************************************
* CONTENT
*
* FUNCTIONS:
*   check_for_cleanup(ref_table OID) RETURNS OID
*   create_array_delete_dummy(table_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS SETOF VOID
*   create_array_delete_function(table_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS SETOF VOID
*   create_delete_function(table_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS SETOF VOID
*   create_ref_array_delete(table_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   create_ref_delete(table_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   create_ref_to_array_delete(table_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   create_ref_to_delete(table_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   create_ref_to_parent_array_delete(table_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   create_ref_to_parent_delete(table_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   create_selfref_array_delete(table_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   create_selfref_delete(table_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   generate_delete_by_id_stmt(table_name TEXT) RETURNS TEXT
*   generate_delete_by_ids_stmt(table_name TEXT) RETURNS TEXT
*   generate_delete_m_ref_by_id_call(m_table_name TEXT, fk_table_name TEXT[], fk_columns TEXT[], schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   generate_delete_m_ref_by_id_stmt(m_table_name TEXT, m_fk_column_name TEXT, fk_table_name TEXT[], fk_columns TEXT[]) RETURNS TEXT
*   generate_delete_m_ref_by_ids_call(m_table_name TEXT, fk_table_name TEXT[], fk_columns TEXT[], schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   generate_delete_m_ref_by_ids_stmt(m_table_name TEXT, m_fk_column_name TEXT, fk_table_name TEXT[], fk_columns TEXT[]) RETURNS TEXT
*   generate_delete_n_m_ref_by_id_call(n_m_table_name TEXT, n_fk_column_name TEXT, m_table_name TEXT, m_fk_column_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   generate_delete_n_m_ref_by_id_stmt(n_m_table_name TEXT, n_fk_column_name TEXT, m_table_name TEXT, m_fk_column_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   generate_delete_n_m_ref_by_ids_call(n_m_table_name TEXT, n_fk_column_name TEXT, m_table_name TEXT, m_fk_column_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   generate_delete_n_m_ref_by_ids_stmt(n_m_table_name TEXT, n_fk_column_name TEXT, m_table_name TEXT, m_fk_column_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   generate_delete_ref_by_id_call(table_name TEXT, fk_column_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   generate_delete_ref_by_id_stmt(table_name TEXT, fk_column_name TEXT) RETURNS TEXT
*   generate_delete_ref_by_ids_call(table_name TEXT, fk_column_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   generate_delete_ref_by_ids_stmt(table_name TEXT, fk_column_name TEXT) RETURNS TEXT
*   generate_delete_selfref_by_id_call(table_name TEXT, self_fk_column_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   generate_delete_selfref_by_ids_call(table_name TEXT, self_fk_column_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   get_short_name(table_name TEXT) RETURNS TEXT
*   query_ref_fk(table_name TEXT, schema_name TEXT DEFAULT 'citydb',
*     OUT root_table_name TEXT, OUT n_table_name TEXT, OUT n_fk_column_name TEXT, OUT ref_depth INTEGER, OUT cleanup_n_table TEXT,
*     OUT m_table_name TEXT, OUT m_fk_column_name TEXT, OUT cleanup_m_table TEXT) RETURNS SETOF RECORD
*   query_ref_tables_and_columns(table_name TEXT, ref_parent_to_exclude TEXT, schema_name TEXT DEFAULT 'citydb',
*     OUT ref_tables TEXT[] DEFAULT '{}', OUT ref_columns TEXT[] DEFAULT '{}') RETURNS RECORD
*   query_ref_to_fk(table_name TEXT, schema_name TEXT DEFAULT 'citydb',
*     OUT ref_table_name TEXT, OUT ref_column_name TEXT, OUT fk_columns TEXT[], OUT cleanup_ref_table BOOLEAN) RETURNS SETOF RECORD
*   query_ref_to_parent_fk(table_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS TEXT
*   query_selfref_fk(table_name TEXT, schema_name TEXT DEFAULT 'citydb') RETURNS SETOF TEXT
*
******************************************************************/

/*
A delete function can consist of up to five parts:
  1. A recursive delete call, if the relation stores tree structures, the FK is set to NO ACTION and parent_id can be NULL
  2. Delete statements (or procedure call) for referencing tables where the FK is set to NO ACTION
  3. The central delete statement that removes the given entry/ies and returns the deleted IDs
  4. Deletes for unreferenced entries in tables where the FK is set to SET NULL or CASCADE when it is a n:m table
  5. If an FK covers the same column(s) as the PK, the referenced parent has to be deleted as well
*/

CREATE OR REPLACE FUNCTION citydb_pkg.get_short_name(table_name TEXT) RETURNS TEXT AS
$$
-- TODO: query a table that stores the short version of a table (maybe objectclass?)
SELECT substr($1, 1, 17);
$$
LANGUAGE sql STRICT;

-- function to check if table requires its own delete function
CREATE OR REPLACE FUNCTION citydb_pkg.check_for_cleanup(ref_table OID) RETURNS OID AS
$$
SELECT
  COALESCE((
    -- reference to parent
    SELECT
      fk.confrelid
    FROM
      pg_constraint fk
    JOIN (
      SELECT
        conrelid,
        conkey
      FROM
        pg_constraint
      WHERE
        contype = 'p'
      ) pk
      ON pk.conrelid = fk.conrelid
     AND pk.conkey = fk.conkey
    WHERE
      fk.conrelid = $1
      AND fk.contype = 'f'
  ),(
    -- referencing tables
    SELECT DISTINCT
      confrelid
    FROM
      pg_constraint
    WHERE
      confrelid = $1
      AND contype = 'f'
      AND confdeltype = 'a'
  ),(
    -- references to tables that need to be cleaned up
    SELECT DISTINCT
      conrelid
    FROM
      pg_constraint
    WHERE
      conrelid = $1
      AND contype = 'f'
      AND confdeltype = 'n'
      AND (confrelid::regclass::text NOT LIKE '%surface_geometry'
       OR conrelid::regclass::text LIKE '%implicit_geometry'
       OR conrelid::regclass::text LIKE '%cityobject_genericattrib'
       OR conrelid::regclass::text LIKE '%cityobjectgroup')
  )) AS cleanup;
$$
LANGUAGE sql STRICT;

CREATE OR REPLACE FUNCTION citydb_pkg.query_ref_tables_and_columns(
  table_name TEXT,
  ref_parent_to_exclude TEXT,
  schema_name TEXT DEFAULT 'citydb',
  OUT ref_tables TEXT[],
  OUT ref_columns TEXT[]
  ) RETURNS RECORD AS
$$
SELECT
  array_agg(c.conrelid::regclass::text) AS ref_tables,
  array_agg(a.attname::text) AS ref_columns
FROM
  pg_constraint c
JOIN
  pg_attribute a
  ON a.attrelid = c.conrelid
 AND a.attnum = ANY (c.conkey)
WHERE
  c.confrelid = ($3 || '.' || $1)::regclass::oid
  AND c.conrelid <> ($3 || '.' || $2)::regclass::oid
  AND c.contype = 'f';
$$
LANGUAGE sql STRICT;


/*****************************
* 1. Self references
*
* Look for nullable FK columns to omit root_id column
*****************************/
CREATE OR REPLACE FUNCTION citydb_pkg.query_selfref_fk(
  table_name TEXT,
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS SETOF TEXT AS 
$$
SELECT
  a.attname::text
FROM
  pg_constraint c
JOIN
  pg_attribute a
  ON a.attrelid = c.conrelid
 AND a.attnum = ANY (c.conkey)
WHERE
  c.conrelid = ($2 || '.' || $1)::regclass::oid
  AND c.conrelid = c.confrelid
  AND c.contype = 'f'
  AND c.confdeltype = 'a'
  AND a.attnotnull = FALSE;
$$
LANGUAGE sql STRICT;

-- ARRAY CASE
CREATE OR REPLACE FUNCTION citydb_pkg.generate_delete_selfref_by_ids_call(
  table_name TEXT,
  self_fk_column_name TEXT,
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS TEXT AS 
$$
SELECT
     E'\n  -- delete referenced parts'
  || E'\n  PERFORM'
  || E'\n    '||$3||'.delete_'||citydb_pkg.get_short_name($1)||'(array_agg(t.id))'
  || E'\n  FROM'
  || E'\n    '||$1||' t,'
  || E'\n    unnest($1) a(a_id)'
  || E'\n  WHERE'
  || E'\n    t.'||$2||' = a.a_id'
  || E'\n    AND t.id != a.a_id;'
  || E'\n';
$$
LANGUAGE sql STRICT;

CREATE OR REPLACE FUNCTION citydb_pkg.create_selfref_array_delete(
  table_name TEXT,
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS TEXT AS
$$
DECLARE
  rec RECORD;
  self_block TEXT := '';
BEGIN
  FOR rec IN (
    SELECT
      parent_column
    FROM
      citydb_pkg.query_selfref_fk($1, $2) AS q(parent_column)
  )
  LOOP
    IF self_block = '' THEN
      -- create a dummy array delete function to avoid endless recursive calls
      PERFORM citydb_pkg.create_array_delete_dummy($1, $2);
    END IF;
    self_block := self_block || citydb_pkg.generate_delete_selfref_by_ids_call($1, rec.parent_column, $2);
  END LOOP;

  RETURN COALESCE(self_block,'');
END;
$$
LANGUAGE plpgsql STRICT;

-- SINGLE CASE
CREATE OR REPLACE FUNCTION citydb_pkg.generate_delete_selfref_by_id_call(
  table_name TEXT,
  self_fk_column_name TEXT,
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS TEXT AS 
$$
SELECT
     E'\n  --delete referenced parts'
  || E'\n  PERFORM'
  || E'\n    '||$3||'.delete_'||citydb_pkg.get_short_name($1)||'(array_agg(id))'
  || E'\n  FROM'
  || E'\n    '||$1
  || E'\n  WHERE'
  || E'\n    ' ||$2|| ' = $1'
  || E'\n    AND id != $1;'
  || E'\n';
$$
LANGUAGE sql STRICT;

CREATE OR REPLACE FUNCTION citydb_pkg.create_selfref_delete(
  table_name TEXT,
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS TEXT AS
$$
DECLARE
  rec RECORD;
  self_block TEXT := '';
BEGIN
  FOR rec IN (
    SELECT
      parent_column
    FROM
      citydb_pkg.query_selfref_fk($1, $2) AS q(parent_column)
  )
  LOOP
    IF self_block = '' THEN
      -- create an array delete function
      PERFORM citydb_pkg.create_array_delete_function($1, $2);
    END IF;
    self_block := self_block || citydb_pkg.generate_delete_selfref_by_id_call($1, rec.parent_column, $2);
  END LOOP;

  RETURN COALESCE(self_block,'');
END;
$$
LANGUAGE plpgsql STRICT;


/*****************************
* 2. Referencing tables
*****************************/
CREATE OR REPLACE FUNCTION citydb_pkg.query_ref_fk(
  table_name TEXT,
  schema_name TEXT DEFAULT 'citydb',
  OUT root_table_name TEXT,
  OUT n_table_name TEXT,
  OUT n_fk_column_name TEXT,
  OUT ref_depth INTEGER,
  OUT cleanup_n_table TEXT,
  OUT m_table_name TEXT,
  OUT m_fk_column_name TEXT,
  OUT m_ref_column_name TEXT,
  OUT cleanup_m_table TEXT
  ) RETURNS SETOF RECORD AS
$$
SELECT
  ref.root_table_name,
  ref.n_table_name::regclass::text,
  ref.n_fk_column_name,
  ref.ref_depth,
  ref.cleanup_n_table,
  m.m_table_name::regclass::text,
  m.m_fk_column_name::text,
  m.m_ref_column_name::text,
  citydb_pkg.check_for_cleanup(m.m_table_name)::regclass::text AS cleanup_m_table
FROM (
  SELECT
    c.confrelid::regclass::text AS root_table_name,
    c.conrelid AS n_table_name,
    c.conkey,
    a.attname::text AS n_fk_column_name,
    COALESCE(n.ref_depth, 1) AS ref_depth,
    citydb_pkg.check_for_cleanup(c.conrelid)::regclass::text AS cleanup_n_table
  FROM
    pg_constraint c
  JOIN
    pg_attribute a
    ON a.attrelid = c.conrelid
   AND a.attnum = ANY (c.conkey)
  LEFT JOIN (
    -- get depth of referencing tables
    WITH RECURSIVE ref_table_depth(parent_table, ref_table, depth) AS (
      SELECT
        confrelid AS parent_table,
        conrelid AS ref_table,
        1 AS depth
      FROM
        pg_constraint
      WHERE
        confrelid = ($2 || '.' || $1)::regclass::oid
        AND conrelid <> confrelid
        AND contype = 'f'
        AND confdeltype = 'a'
      UNION ALL
        SELECT
          r.confrelid AS parent_table,
          r.conrelid AS ref_table,
          d.depth + 1 AS depth
        FROM
          pg_constraint r,
          ref_table_depth d
        WHERE
          d.ref_table = r.confrelid
          AND d.ref_table <> r.conrelid
          AND r.contype = 'f'
          AND r.confdeltype = 'a'
    )
    SELECT
      parent_table,
      max(depth) AS ref_depth
    FROM
      ref_table_depth
    GROUP BY
      parent_table
    ) n
    ON n.parent_table = c.conrelid
  WHERE
    c.confrelid = ($2 || '.' || $1)::regclass::oid
    AND c.conrelid <> c.confrelid
    AND c.contype = 'f'
    AND c.confdeltype = 'a'
) ref
-- get n:m tables which are the NULL candidates from the n block
-- the FK has to be set to CASCADE to decide for cleanup
LEFT JOIN LATERAL (
  SELECT
    mn.confrelid AS m_table_name,
    mna.attname AS m_fk_column_name,
    mna_ref.attname AS m_ref_column_name
  FROM
    pg_constraint mn
  JOIN
    pg_attribute mna
    ON mna.attrelid = mn.conrelid
   AND mna.attnum = ANY (mn.conkey)
  JOIN
    pg_attribute mna_ref
    ON mna_ref.attrelid = mn.confrelid
   AND mna_ref.attnum = ANY (mn.confkey)
  JOIN
    pg_constraint pk
    ON pk.conrelid = mn.conrelid
   AND pk.conkey @> (ref.conkey || mn.conkey || '{}')
  WHERE
    mn.conrelid = ref.n_table_name
    AND ref.cleanup_n_table IS NULL
    AND mn.confrelid <> ref.n_table_name
    AND mn.contype = 'f'
    AND mn.confdeltype = 'c'
    AND pk.contype = 'p'
  ) m ON (true)
WHERE
  ref.root_table_name <> 'cityobject'
  OR ref.cleanup_n_table <> 'cityobject'
ORDER BY
  ref.ref_depth DESC NULLS FIRST,
  ref.n_table_name,
  m.m_table_name;
$$
LANGUAGE sql STRICT;

-- ARRAY CASE
CREATE OR REPLACE FUNCTION citydb_pkg.generate_delete_ref_by_ids_stmt(
  table_name TEXT,
  fk_column_name TEXT
  ) RETURNS TEXT AS
$$
SELECT
     E'\n  -- delete '||$1||'s'
  || E'\n  DELETE FROM'
  || E'\n    '||$1||' t'
  || E'\n  USING'
  || E'\n    unnest($1) a(a_id)'
  || E'\n  WHERE'
  || E'\n    t.'||$2||E' = a.a_id;\n';
$$
LANGUAGE sql STRICT;

CREATE OR REPLACE FUNCTION citydb_pkg.generate_delete_ref_by_ids_call(
  table_name TEXT,
  fk_column_name TEXT,
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS TEXT AS
$$
SELECT
     E'\n  -- delete '||$1||'s'
  || E'\n  PERFORM'
  || E'\n    '||$3||'.delete_'||citydb_pkg.get_short_name($1)||E'(array_agg(t.id))'
  || E'\n  FROM'
  || E'\n    '||$1|| ' t,'
  || E'\n    unnest($1) a(a_id)'
  || E'\n  WHERE'
  || E'\n    t.'||$2||E' = a.a_id;\n';
$$
LANGUAGE sql STRICT;

CREATE OR REPLACE FUNCTION citydb_pkg.generate_delete_m_ref_by_ids_stmt(
  m_table_name TEXT,
  m_fk_column_name TEXT,
  fk_table_name TEXT[],
  fk_columns TEXT[]
  ) RETURNS TEXT AS 
$$
SELECT
     E'\n  -- delete '||$1||'(s) not being referenced any more'
  || E'\n  IF -1 = ALL('||citydb_pkg.get_short_name($1)||'_ids) IS NOT NULL THEN'
  || E'\n    DELETE FROM'
  || E'\n      '||$1||' m'
  || E'\n    USING'
  || E'\n      (SELECT DISTINCT unnest('||citydb_pkg.get_short_name($1)||'_ids) AS a_id) a'
  || E'\n    '
  || string_agg(
            'LEFT JOIN'
  || E'\n      '||t.tab||' n'||c.i
  || E'\n      ON n'||c.i||'.'||c.col||' = a.a_id',
     E'\n    ')
  || E'\n    WHERE'
  || E'\n      m.'||$2||' = a.a_id'
  || E'\n      AND '
  || string_agg(
              'n'||c.i||'.'||c.col||' IS NULL',
     E'\n      AND ') || ';'
  || E'\n  END IF;\n'
FROM
  unnest($3) WITH ORDINALITY AS t(tab, i),
  unnest($4) WITH ORDINALITY AS c(col, i)
WHERE
  t.i = c.i;
$$
LANGUAGE sql STRICT;

CREATE OR REPLACE FUNCTION citydb_pkg.generate_delete_m_ref_by_ids_call(
  m_table_name TEXT,
  fk_table_name TEXT[],
  fk_columns TEXT[],
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS TEXT AS 
$$
SELECT
     E'\n  -- delete '||$1||'(s) not being referenced any more'
  || E'\n  IF -1 = ALL('||citydb_pkg.get_short_name($1)||'_ids) IS NOT NULL THEN'
  || E'\n    PERFORM'
  || E'\n      '||$4||'.delete_'||citydb_pkg.get_short_name($1)||'(array_agg(a.a_id))'
  || E'\n    FROM'
  || E'\n      (SELECT DISTINCT unnest('||citydb_pkg.get_short_name($1)||'_ids) AS a_id) a'
  || E'\n    '
  || string_agg(
            'LEFT JOIN'
  || E'\n      '||t.tab||' n'||c.i
  || E'\n      ON n'||c.i||'.'||c.col||' = a.a_id',
     E'\n    ')
  || E'\n    WHERE'
  || E'\n      '
  || string_agg(
              'n'||c.i||'.'||c.col||' IS NULL',
     E'\n      AND ') || ';'
  || E'\n  END IF;\n'
FROM
  unnest($2) WITH ORDINALITY AS t(tab, i),
  unnest($3) WITH ORDINALITY AS c(col, i)
WHERE
  t.i = c.i;
$$
LANGUAGE sql STRICT;

CREATE OR REPLACE FUNCTION citydb_pkg.generate_delete_n_m_ref_by_ids_stmt(
  n_m_table_name TEXT,
  n_fk_column_name TEXT,
  m_table_name TEXT,
  m_fk_column_name TEXT,
  m_ref_column_name TEXT,
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS TEXT AS 
$$
SELECT
     E'\n  -- delete references to '||$3||'s'
  || E'\n  WITH delete_'||citydb_pkg.get_short_name($3)||'_refs AS ('
  || E'\n    DELETE FROM'
  || E'\n      '||$1||' t'
  || E'\n    USING'
  || E'\n      unnest($1) a(a_id)'
  || E'\n    WHERE'
  || E'\n      t.'||$2||' = a.a_id'
  || E'\n    RETURNING'
  || E'\n      t.'||$4
  || E'\n  )'
  || E'\n  SELECT'
  || E'\n    array_agg('||$4||')'
  || E'\n  INTO'
  || E'\n    '||citydb_pkg.get_short_name($3)||'_ids'
  || E'\n  FROM'
  || E'\n    delete_'||citydb_pkg.get_short_name($3)||'_refs;'
  || E'\n'
  || citydb_pkg.generate_delete_m_ref_by_ids_stmt(
       $3, $5, ARRAY[$1] || COALESCE(ref_tables, '{}'), ARRAY[$4] || COALESCE(ref_columns, '{}')
     )
FROM
  citydb_pkg.query_ref_tables_and_columns($3, $1, $6) AS r(ref_tables, ref_columns);
$$
LANGUAGE sql STRICT;

CREATE OR REPLACE FUNCTION citydb_pkg.generate_delete_n_m_ref_by_ids_call(
  n_m_table_name TEXT,
  n_fk_column_name TEXT,
  m_table_name TEXT,
  m_fk_column_name TEXT,
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS TEXT AS 
$$
SELECT
     E'\n  -- delete references to '||$3||'s'
  || E'\n  WITH delete_'||citydb_pkg.get_short_name($3)||'_refs AS ('
  || E'\n    DELETE FROM'
  || E'\n      '||$1||' t'
  || E'\n    USING'
  || E'\n      unnest($1) a(a_id)'
  || E'\n    WHERE'
  || E'\n      t.'||$2||' = a.a_id'
  || E'\n    RETURNING'
  || E'\n      t.'||$4
  || E'\n  )'
  || E'\n  SELECT'
  || E'\n    array_agg('||$4||')'
  || E'\n  INTO'
  || E'\n    '||citydb_pkg.get_short_name($3)||'_ids'
  || E'\n  FROM'
  || E'\n    delete_'||citydb_pkg.get_short_name($3)||'_refs;'
  || E'\n'
  || citydb_pkg.generate_delete_m_ref_by_ids_call(
       $3, ARRAY[$1] || COALESCE(ref_tables, '{}'), ARRAY[$4] || COALESCE(ref_columns, '{}'), $5
     )
FROM
  citydb_pkg.query_ref_tables_and_columns($3, $1, $5) AS r(ref_tables, ref_columns);
$$
LANGUAGE sql STRICT;

CREATE OR REPLACE FUNCTION citydb_pkg.create_ref_array_delete(
  table_name TEXT,
  schema_name TEXT DEFAULT 'citydb',
  OUT vars TEXT,
  OUT ref_block TEXT
  ) RETURNS RECORD AS
$$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN (
    SELECT * FROM citydb_pkg.query_ref_fk($1, $2)
  )
  LOOP
    IF vars IS NULL THEN
      vars := '';
      ref_block := '';
    END IF;

    IF (
      rec.ref_depth > 1
      OR rec.cleanup_n_table IS NOT NULL
      OR rec.cleanup_m_table IS NOT NULL
    ) THEN
      -- function call required, so create function first
      PERFORM
        citydb_pkg.create_array_delete_function(
          COALESCE(rec.m_table_name, rec.n_table_name), $2
        );

      IF rec.m_table_name IS NULL THEN
        IF rec.root_table_name = rec.cleanup_n_table THEN
          ref_block := ref_block
            || E'\n  -- delete '||rec.n_table_name||'s'
            || E'\n  PERFORM '||$2||'.delete_'||citydb_pkg.get_short_name(rec.n_table_name)||E'($1);\n';
        ELSE
          ref_block := ref_block || citydb_pkg.generate_delete_ref_by_ids_call(rec.n_table_name, rec.n_fk_column_name, $2);
        END IF;
      ELSE
        vars := vars ||E'\n  ' || citydb_pkg.get_short_name(rec.m_table_name) || '_ids int[] := ''{}'';';
        ref_block := ref_block || citydb_pkg.generate_delete_n_m_ref_by_ids_call(rec.n_table_name, rec.n_fk_column_name, rec.m_table_name, rec.m_fk_column_name, $2);
      END IF;
    ELSE
      IF rec.m_table_name IS NULL THEN
        ref_block := ref_block || citydb_pkg.generate_delete_ref_by_ids_stmt(rec.n_table_name, rec.n_fk_column_name);
      ELSE
        vars := vars || E'\n  ' || citydb_pkg.get_short_name(rec.m_table_name) || '_ids int[] := ''{}'';';
        ref_block := ref_block || citydb_pkg.generate_delete_n_m_ref_by_ids_stmt(rec.n_table_name, rec.n_fk_column_name, rec.m_table_name, rec.m_fk_column_name, rec.m_ref_column_name, $2);
      END IF;
    END IF;
  END LOOP;

  RETURN;
END;
$$
LANGUAGE plpgsql STRICT;

-- SINGLE CASE
CREATE OR REPLACE FUNCTION citydb_pkg.generate_delete_ref_by_id_stmt(
  table_name TEXT,
  fk_column_name TEXT
  ) RETURNS TEXT AS 
$$
SELECT
     E'\n  -- delete '||$1||'s'
  || E'\n  DELETE FROM'
  || E'\n    '||$1
  || E'\n  WHERE'
  || E'\n    '||$2||E' = $1;\n';
$$
LANGUAGE sql STRICT;

CREATE OR REPLACE FUNCTION citydb_pkg.generate_delete_ref_by_id_call(
  table_name TEXT,
  fk_column_name TEXT,
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS TEXT AS 
$$
SELECT
     E'\n  -- delete '||$1||'s'
  || E'\n  PERFORM'
  || E'\n    '||$3||'.delete_'||citydb_pkg.get_short_name($1)||E'(array_agg(id))'
  || E'\n  FROM'
  || E'\n    '||$1
  || E'\n  WHERE'
  || E'\n    '||$2||E' = $1;\n';
$$
LANGUAGE sql STRICT;

CREATE OR REPLACE FUNCTION citydb_pkg.generate_delete_m_ref_by_id_stmt(
  m_table_name TEXT,
  m_fk_column_name TEXT,
  fk_table_name TEXT[],
  fk_columns TEXT[]
  ) RETURNS TEXT AS 
$$
SELECT
     E'\n  -- delete '||$1||'(s) not being referenced any more'
  || E'\n  IF '||citydb_pkg.get_short_name($1)||'_ref_id IS NOT NULL THEN'
  || E'\n    DELETE FROM'
  || E'\n      '||$1||' m'
  || E'\n    USING'
  || E'\n      (VALUES ('||citydb_pkg.get_short_name($1)||'_ref_id)) a(a_id)'
  || E'\n    '
  || string_agg(
            'LEFT JOIN'
  || E'\n      '||t.tab||' n'||c.i
  || E'\n      ON n'||c.i||'.'||c.col||' = a.a_id',
     E'\n    ')
  || E'\n    WHERE'
  || E'\n      m.'||$2||' = a.a_id'
  || E'\n      AND '
  || string_agg(
              'n'||c.i||'.'||c.col||' IS NULL',
     E'\n      AND ') || ';'
  || E'\n  END IF;\n'
FROM
  unnest($3) WITH ORDINALITY AS t(tab, i),
  unnest($4) WITH ORDINALITY AS c(col, i)
WHERE
  t.i = c.i;
$$
LANGUAGE sql STRICT;

CREATE OR REPLACE FUNCTION citydb_pkg.generate_delete_m_ref_by_id_call(
  m_table_name TEXT,
  fk_table_name TEXT[],
  fk_columns TEXT[],
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS TEXT AS 
$$
SELECT
     E'\n  -- delete '||$1||'(s) not being referenced any more'
  || E'\n  IF '||citydb_pkg.get_short_name($1)||'_ref_id IS NOT NULL THEN'
  || E'\n    PERFORM'
  || E'\n      '||$4||'.delete_'||citydb_pkg.get_short_name($1)||'(a.a_id)'
  || E'\n    FROM'
  || E'\n      (VALUES ('||citydb_pkg.get_short_name($1)||'_ref_id)) a(a_id)'
  || E'\n    '
  || string_agg(
            'LEFT JOIN'
  || E'\n      '||t.tab||' n'||c.i
  || E'\n      ON n'||c.i||'.'||c.col||' = a.a_id',
     E'\n    ')
  || E'\n    WHERE'
  || E'\n      '
  || string_agg(
              'n'||c.i||'.'||c.col||' IS NULL',
     E'\n      AND ') || ';'
  || E'\n  END IF;\n'
FROM
  unnest($2) WITH ORDINALITY AS t(tab, i),
  unnest($3) WITH ORDINALITY AS c(col, i)
WHERE
  t.i = c.i;
$$
LANGUAGE sql STRICT;

CREATE OR REPLACE FUNCTION citydb_pkg.generate_delete_n_m_ref_by_id_stmt(
  n_m_table_name TEXT,
  n_fk_column_name TEXT,
  m_table_name TEXT,
  m_fk_column_name TEXT,
  m_ref_column_name TEXT,
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS TEXT AS 
$$
SELECT
     E'\n  -- delete references to '||$3||'s'
  || E'\n  WITH delete_'||citydb_pkg.get_short_name($3)||'_refs AS ('
  || E'\n    DELETE FROM'
  || E'\n      '||$1
  || E'\n    WHERE'
  || E'\n      '||$2||' = $1'
  || E'\n    RETURNING'
  || E'\n      '||$4
  || E'\n  )'
  || E'\n  SELECT'
  || E'\n    array_agg('||$4||')'
  || E'\n  INTO'
  || E'\n    '||citydb_pkg.get_short_name($3)||'_ids'
  || E'\n  FROM'
  || E'\n    delete_'||citydb_pkg.get_short_name($3)||'_refs;'
  || E'\n'
  || citydb_pkg.generate_delete_m_ref_by_ids_stmt(
       $3, $5, ARRAY[$1] || COALESCE(ref_tables, '{}'), ARRAY[$4] || COALESCE(ref_columns, '{}')
     )
FROM
  citydb_pkg.query_ref_tables_and_columns($3, $1, $6) AS r(ref_tables, ref_columns);
$$
LANGUAGE sql STRICT;

CREATE OR REPLACE FUNCTION citydb_pkg.generate_delete_n_m_ref_by_id_call(
  n_m_table_name TEXT,
  n_fk_column_name TEXT,
  m_table_name TEXT,
  m_fk_column_name TEXT,
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS TEXT AS 
$$
SELECT
     E'\n  -- delete references to '||$3||'s'
  || E'\n  WITH delete_'||citydb_pkg.get_short_name($3)||'_refs AS ('
  || E'\n    DELETE FROM'
  || E'\n      '||$1
  || E'\n    WHERE'
  || E'\n      '||$2||' = $1'
  || E'\n    RETURNING'
  || E'\n      '||$4
  || E'\n  )'
  || E'\n  SELECT'
  || E'\n    array_agg('||$4||')'
  || E'\n  INTO'
  || E'\n    '||citydb_pkg.get_short_name($3)||'_ids'
  || E'\n  FROM'
  || E'\n    delete_'||citydb_pkg.get_short_name($3)||'_refs;'
  || E'\n'
  || citydb_pkg.generate_delete_m_ref_by_ids_call(
       $3, ARRAY[$1] || COALESCE(ref_tables, '{}'), ARRAY[$4] || COALESCE(ref_columns, '{}'), $5
     )
FROM
  citydb_pkg.query_ref_tables_and_columns($3, $1, $5) AS r(ref_tables, ref_columns);
$$
LANGUAGE sql STRICT;

CREATE OR REPLACE FUNCTION citydb_pkg.create_ref_delete(
  table_name TEXT,
  schema_name TEXT DEFAULT 'citydb',
  OUT vars TEXT,
  OUT ref_block TEXT
  ) RETURNS RECORD AS
$$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN (
    SELECT * FROM citydb_pkg.query_ref_fk($1, $2)
  )
  LOOP
    IF vars IS NULL THEN
      vars := '';
      ref_block := '';
    END IF;

    IF (
      rec.ref_depth > 1
      OR rec.cleanup_n_table IS NOT NULL
      OR rec.cleanup_m_table IS NOT NULL
    ) THEN
      -- function call required, so create function first
      PERFORM
        citydb_pkg.create_array_delete_function(
          COALESCE(rec.m_table_name, rec.n_table_name), $2
        );

      IF rec.m_table_name IS NULL THEN
        IF rec.root_table_name = rec.cleanup_n_table THEN
          ref_block := ref_block
            || E'\n  -- delete '||rec.n_table_name
            || E'\n  PERFORM '||$2||'.delete_'||citydb_pkg.get_short_name(rec.n_table_name)||E'($1);\n';
        ELSE
          ref_block := ref_block || citydb_pkg.generate_delete_ref_by_id_call(rec.n_table_name, rec.n_fk_column_name, $2);
        END IF;
      ELSE
        vars := vars || E'\n  ' || citydb_pkg.get_short_name(rec.m_table_name) || '_ids int[] := ''{}'';';
        ref_block := ref_block || citydb_pkg.generate_delete_n_m_ref_by_id_call(rec.n_table_name, rec.n_fk_column_name, rec.m_table_name, rec.m_fk_column_name, $2);
      END IF;
    ELSE
      IF rec.m_table_name IS NULL THEN
        ref_block := ref_block||citydb_pkg.generate_delete_ref_by_id_stmt(rec.n_table_name, rec.n_fk_column_name);
      ELSE
        vars := vars || E'\n  ' || citydb_pkg.get_short_name(rec.m_table_name) || '_ids int[] := ''{}'';';
        ref_block := ref_block || citydb_pkg.generate_delete_n_m_ref_by_id_stmt(rec.n_table_name, rec.n_fk_column_name, rec.m_table_name, rec.m_fk_column_name, rec.m_ref_column_name, $2);
      END IF;
    END IF;
  END LOOP;

  RETURN;
END;
$$
LANGUAGE plpgsql STRICT;


/*****************************
* 3. Main delete
*
* statements are not closed because more columns might be returned
*****************************/
-- ARRAY CASE
CREATE OR REPLACE FUNCTION citydb_pkg.generate_delete_by_ids_stmt(
  table_name TEXT
  ) RETURNS TEXT AS 
$$
SELECT  '  DELETE FROM'
  || E'\n      '||$1||' t'
  || E'\n    USING'
  || E'\n      unnest($1) a(a_id)'
  || E'\n    WHERE'
  || E'\n      t.id = a.a_id'
  || E'\n    RETURNING'
  || E'\n      id';
$$
LANGUAGE sql STRICT;

-- SINGLE CASE
CREATE OR REPLACE FUNCTION citydb_pkg.generate_delete_by_id_stmt(
  table_name TEXT
  ) RETURNS TEXT AS 
$$
SELECT
     E'\n  DELETE FROM'
  || E'\n    '||$1
  || E'\n  WHERE'
  || E'\n    id = $1'
  || E'\n  RETURNING'
  || E'\n    id';
$$
LANGUAGE sql STRICT;


/*****************************
* 4. FKs in table
*****************************/
CREATE OR REPLACE FUNCTION citydb_pkg.query_ref_to_fk(
  table_name TEXT,
  schema_name TEXT DEFAULT 'citydb',
  OUT ref_table_name TEXT,
  OUT ref_column_name TEXT,
  OUT fk_columns TEXT[],
  OUT cleanup_ref_table BOOLEAN
  ) RETURNS SETOF RECORD AS
$$
SELECT
  c.confrelid::regclass::text AS ref_table_name,
  a_ref.attname::text AS ref_column_name,
  array_agg(a.attname::text ORDER BY a.attnum) AS fk_columns,
  citydb_pkg.check_for_cleanup(c.confrelid) IS NOT NULL AS cleanup_ref_table
FROM
  pg_constraint c
JOIN
  pg_attribute a
  ON a.attrelid = c.conrelid
 AND a.attnum = ANY (c.conkey)
JOIN
  pg_attribute a_ref
  ON a_ref.attrelid = c.confrelid
 AND a_ref.attnum = ANY (c.confkey)
WHERE
  c.conrelid = ($2 || '.' || $1)::regclass::oid
  AND c.conrelid <> c.confrelid
  AND c.contype = 'f'
  AND c.confdeltype = 'n'
  AND (c.confrelid::regclass::text NOT LIKE '%surface_geometry'
   OR c.conrelid::regclass::text LIKE '%implicit_geometry'
   OR c.conrelid::regclass::text LIKE '%cityobject_genericattrib'
   OR c.conrelid::regclass::text LIKE '%cityobjectgroup')
GROUP BY
  c.confrelid,
  a_ref.attname;
$$
LANGUAGE sql STRICT;

-- ARRAY CASE
CREATE OR REPLACE FUNCTION citydb_pkg.create_ref_to_array_delete(
  table_name TEXT,
  schema_name TEXT DEFAULT 'citydb',
  OUT vars TEXT,
  OUT returning_block TEXT,
  OUT collect_block TEXT,
  OUT into_block TEXT,
  OUT fk_block TEXT
  ) RETURNS RECORD AS
$$
DECLARE
  rec RECORD;
  ref_to_ref_tables TEXT[] := '{}';
  ref_to_ref_columns TEXT[] := '{}';
BEGIN
  FOR rec IN (
    SELECT * FROM citydb_pkg.query_ref_to_fk($1, $2)
  )
  LOOP
    IF vars IS NULL THEN
      vars := '';
      returning_block := '';
      collect_block := '';
      into_block := '';
      fk_block := '';
    END IF;

    vars := vars || E'\n  ' || citydb_pkg.get_short_name(rec.ref_table_name) || '_ids int[] := ''{}'';';
    returning_block := returning_block || E',\n      ' || array_to_string(rec.fk_columns, E',\n      ');
    collect_block := collect_block || E',\n    '
      || (SELECT
            string_agg('array_agg('||col||')', E' ||\n    ')
          FROM
            unnest(rec.fk_columns) AS c(col));

    into_block := into_block || E',\n    ' || citydb_pkg.get_short_name(rec.ref_table_name)||'_ids';

    -- prepare arrays for referencing tables and columns to cleanup
    ref_to_ref_tables := array_fill($1, ARRAY[array_length(rec.fk_columns, 1)]);
    ref_to_ref_columns := rec.fk_columns;
    IF
      rec.ref_table_name <> 'implicit_geometry'
      AND rec.ref_table_name <> 'surface_geometry'
    THEN
      SELECT
        ref_to_ref_tables || COALESCE(r.ref_tables, '{}'),
        ref_to_ref_columns || COALESCE(r.ref_columns, '{}')
      INTO
        ref_to_ref_tables,
        ref_to_ref_columns
      FROM
        citydb_pkg.query_ref_tables_and_columns(
          rec.ref_table_name, $1, $2
        ) AS r(ref_tables, ref_columns);
    END IF;

    IF rec.cleanup_ref_table THEN
      -- function call required, so create function first
      PERFORM citydb_pkg.create_array_delete_function(rec.ref_table_name, $2);
      fk_block := fk_block || citydb_pkg.generate_delete_m_ref_by_ids_call(rec.ref_table_name, ref_to_ref_tables, ref_to_ref_columns, $2);
    ELSE
      fk_block := fk_block || citydb_pkg.generate_delete_m_ref_by_ids_stmt(rec.ref_table_name, rec.ref_column_name, ref_to_ref_tables, ref_to_ref_columns);
    END IF;
  END LOOP;

  RETURN;
END;
$$
LANGUAGE plpgsql STRICT;

-- SINGLE CASE
CREATE OR REPLACE FUNCTION citydb_pkg.create_ref_to_delete(
  table_name TEXT,
  schema_name TEXT DEFAULT 'citydb',
  OUT vars TEXT,
  OUT returning_block TEXT,
  OUT into_block TEXT,
  OUT fk_block TEXT
  ) RETURNS RECORD AS
$$
DECLARE
  rec RECORD;
  ref_to_ref_tables TEXT[] := '{}';
  ref_to_ref_columns TEXT[] := '{}';
BEGIN
  FOR rec IN (
    SELECT * FROM citydb_pkg.query_ref_to_fk($1, $2)
  )
  LOOP
    IF vars IS NULL THEN
      vars := '';
      returning_block := '';
      into_block := '';
      fk_block := '';
    END IF;

    IF array_length(rec.fk_columns, 1) > 1 THEN
      vars := vars || E'\n  ' || citydb_pkg.get_short_name(rec.ref_table_name) || '_ids int[] := ''{}'';';
      returning_block := returning_block || ','
        || E'\n    ARRAY['
        || E'\n    ' || array_to_string(rec.fk_columns, E',\n    ')
        || E'\n    ]';
      into_block := into_block || E',\n    ' || citydb_pkg.get_short_name(rec.ref_table_name)||'_ids';
    ELSE
      vars := vars || E'\n  ' || citydb_pkg.get_short_name(rec.ref_table_name)||'_ref_id int;';
      returning_block := returning_block || E',\n      ' || array_to_string(rec.fk_columns, E',\n      ');
      into_block := into_block || E',\n    ' || citydb_pkg.get_short_name(rec.ref_table_name) || '_ref_id';
    END IF;

    -- prepare arrays for referencing tables and columns to cleanup
    ref_to_ref_tables := array_fill($1, ARRAY[array_length(rec.fk_columns, 1)]);
    ref_to_ref_columns := rec.fk_columns;
    IF
      rec.ref_table_name <> 'implicit_geometry'
      AND rec.ref_table_name <> 'surface_geometry'
    THEN
      SELECT
        ref_to_ref_tables || COALESCE(r.ref_tables, '{}'),
        ref_to_ref_columns || COALESCE(r.ref_columns, '{}')
      INTO
        ref_to_ref_tables,
        ref_to_ref_columns
      FROM
        citydb_pkg.query_ref_tables_and_columns(
          rec.ref_table_name, $1, $2
        ) AS r(ref_tables, ref_columns);
    END IF;

    IF rec.cleanup_ref_table THEN
      -- function call required, so create function first
      IF array_length(rec.fk_columns, 1) > 1 THEN
        PERFORM citydb_pkg.create_array_delete_function(rec.ref_table_name, $2);
        fk_block := fk_block || citydb_pkg.generate_delete_m_ref_by_ids_call(rec.ref_table_name, ref_to_ref_tables, ref_to_ref_columns, $2);
      ELSE
        PERFORM citydb_pkg.create_delete_function(rec.ref_table_name, $2);
        fk_block := fk_block || citydb_pkg.generate_delete_m_ref_by_id_call(rec.ref_table_name, ref_to_ref_tables, ref_to_ref_columns, $2);
      END IF;
    ELSE
      IF array_length(rec.fk_columns, 1) > 1 THEN
        fk_block := fk_block || citydb_pkg.generate_delete_m_ref_by_ids_stmt(rec.ref_table_name, rec.ref_column_name, ref_to_ref_tables, ref_to_ref_columns);
      ELSE
        fk_block := fk_block || citydb_pkg.generate_delete_m_ref_by_id_stmt(rec.ref_table_name, rec.ref_column_name, ref_to_ref_tables, ref_to_ref_columns);
      END IF;
    END IF;
  END LOOP;

  RETURN;
END;
$$
LANGUAGE plpgsql STRICT;


/*****************************
* 5. FK which is PK 
*****************************/
CREATE OR REPLACE FUNCTION citydb_pkg.query_ref_to_parent_fk(
  table_name TEXT,
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS TEXT AS
$$
SELECT 
  f.confrelid::regclass::text AS parent_table
FROM
  pg_constraint f,
  pg_constraint p
WHERE
  f.conrelid = ($2 || '.' || $1)::regclass::oid
  AND p.conrelid = ($2 || '.' || $1)::regclass::oid
  AND f.conkey = p.conkey
  AND f.contype = 'f'
  AND p.contype = 'p';
$$
LANGUAGE sql STRICT;

-- ARRAY CASE
CREATE OR REPLACE FUNCTION citydb_pkg.create_ref_to_parent_array_delete(
  table_name TEXT,
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS TEXT AS
$$
DECLARE
  parent_table TEXT;
  parent_block TEXT := '';
BEGIN
  parent_table := citydb_pkg.query_ref_to_parent_fk($1, $2);

  IF parent_table IS NOT NULL THEN
    IF parent_table = 'cityobject' THEN
      PERFORM citydb_pkg.create_array_delete_function(parent_table, $2);
    END IF;
    parent_block := parent_block
      || E'\n  -- delete '||parent_table
      || E'\n  PERFORM '||$2||'.delete_'||citydb_pkg.get_short_name(parent_table)||E'(deleted_ids);\n';
  END IF;

  RETURN parent_block;
END;
$$
LANGUAGE plpgsql;

-- SINGLE CASE
CREATE OR REPLACE FUNCTION citydb_pkg.create_ref_to_parent_delete(
  table_name TEXT,
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS TEXT AS
$$
DECLARE
  parent_table TEXT;
  parent_block TEXT := '';
BEGIN
  parent_table := citydb_pkg.query_ref_to_parent_fk($1, $2);

  IF parent_table IS NOT NULL THEN
    IF parent_table = 'cityobject' THEN
      PERFORM citydb_pkg.create_delete_function(parent_table, $2);
    END IF;
    parent_block := parent_block
      || E'\n  -- delete '||parent_table
      || E'\n  PERFORM '||$2||'.delete_'||citydb_pkg.get_short_name(parent_table)||E'(deleted_id);\n';
  END IF;

  RETURN parent_block;
END;
$$
LANGUAGE plpgsql;


/**************************
* CREATE DELETE FUNCTION
**************************/
-- dummy function to compile array delete functions with recursions
CREATE OR REPLACE FUNCTION citydb_pkg.create_array_delete_dummy(
  table_name TEXT,
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS SETOF VOID AS 
$$
DECLARE
  ddl_command TEXT := 'CREATE OR REPLACE FUNCTION '||schema_name||'.delete_' ||citydb_pkg.get_short_name($1)|| E'(int[]) RETURNS SETOF int AS\n$body$'
    || E'\nDECLARE\n  deleted_ids int[] := ''{}'';'
    || E'\nBEGIN\n  RETURN QUERY SELECT unnest(deleted_ids);\nEND;'
    || E'\n$body$\nLANGUAGE plpgsql STRICT;';
BEGIN
  EXECUTE ddl_command;
END;
$$
LANGUAGE plpgsql STRICT;

-- ARRAY CASE
CREATE OR REPLACE FUNCTION citydb_pkg.create_array_delete_function(
  table_name TEXT,
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS SETOF VOID AS 
$$
DECLARE
  ddl_command TEXT := 'CREATE OR REPLACE FUNCTION '||schema_name||'.delete_' ||citydb_pkg.get_short_name($1)|| E'(int[]) RETURNS SETOF int AS\n$body$';
  declare_block TEXT := E'\nDECLARE\n  deleted_ids int[] := ''{}'';';
  pre_block TEXT := '';
  post_block TEXT := '';
  delete_agg_start TEXT := E'\n  WITH delete_objects AS (\n  ';
  delete_block TEXT := '';
  delete_agg_end TEXT := E'\n  )\n  SELECT\n    array_agg(id)';
  return_block TEXT := E'\n  RETURN QUERY\n    SELECT unnest(deleted_ids);';
BEGIN
  -- SELF REFERENCES
  pre_block := citydb_pkg.create_selfref_array_delete($1, $2);

  -- REFERENCING TABLES
  SELECT
    declare_block || COALESCE(vars, ''),
    pre_block || COALESCE(ref_block, '')
  INTO
    declare_block,
    pre_block
  FROM
    citydb_pkg.create_ref_array_delete($1, $2);

  -- MAIN DELETE
  delete_block := generate_delete_by_ids_stmt($1);

  -- FOREIGN KEY which are set to ON DELETE SET NULL
  SELECT
    declare_block || COALESCE(vars, ''),
    delete_block || COALESCE(returning_block, ''),
    delete_agg_end || COALESCE(collect_block, '') 
      || E'\n  INTO\n    deleted_ids'
      || COALESCE(into_block, '')
      || E'\n  FROM\n    delete_objects;\n',
    COALESCE(fk_block, '')
  INTO
    declare_block,
    delete_block,
    delete_agg_end,
    post_block
  FROM
    citydb_pkg.create_ref_to_array_delete($1, $2);

  -- FOREIGN KEY which cover same columns as primary key
  post_block := post_block || citydb_pkg.create_ref_to_parent_array_delete($1, $2);
  
  -- if there is no FK to clean up IDs can be returned directly with DELETE statement 
  IF post_block = '' THEN
    delete_agg_start := E'\n  RETURN QUERY\n  ';
    delete_block := delete_block;
    delete_agg_end := ';';
    return_block := '';
  END IF;

  -- putting all together
  IF pre_block = '' AND post_block = '' THEN
    ddl_command := ddl_command
      || E'\n  -- delete '||$1||'s'
      || E'\n' || delete_block || ';'
      || E'\n$body$'
      || E'\nLANGUAGE sql STRICT';
  ELSE
    ddl_command := ddl_command
      || declare_block
      || E'\nBEGIN'
      || pre_block
      || E'\n  -- delete '||$1||'s'
      || delete_agg_start
      || delete_block
      || delete_agg_end
      || post_block
      || return_block
      || E'\nEND;'
      || E'\n$body$'
      || E'\nLANGUAGE plpgsql STRICT';
  END IF;

  EXECUTE ddl_command;
END;
$$
LANGUAGE plpgsql STRICT;

-- SINGLE CASE
CREATE OR REPLACE FUNCTION citydb_pkg.create_delete_function(
  table_name TEXT,
  schema_name TEXT DEFAULT 'citydb'
  ) RETURNS SETOF VOID AS 
$$
DECLARE
  ddl_command TEXT := 'CREATE OR REPLACE FUNCTION '||schema_name||'.delete_'||citydb_pkg.get_short_name($1)|| E'(int) RETURNS int AS\n$body$';
  declare_block TEXT := E'\nDECLARE\n  deleted_id INTEGER;';
  pre_block TEXT := '';
  post_block TEXT := '';
  delete_block TEXT := '';
  delete_into_block TEXT := E'\n  INTO\n    deleted_id';
BEGIN
  -- SELF REFERENCES
  pre_block := citydb_pkg.create_selfref_delete($1, $2);

  -- REFERENCING TABLES
  SELECT
    declare_block || COALESCE(vars, ''),
    pre_block || COALESCE(ref_block, '')
  INTO
    declare_block,
    pre_block
  FROM
    citydb_pkg.create_ref_delete($1, $2);

  -- MAIN DELETE
  delete_block := generate_delete_by_id_stmt($1);

  -- FOREIGN KEY which are set to ON DELETE SET NULL
  SELECT
    declare_block || COALESCE(vars, ''),
    delete_block || COALESCE(returning_block, ''),
    delete_into_block || COALESCE(into_block, '') || E';\n',
    COALESCE(fk_block, '')
  INTO
    declare_block,
    delete_block,
    delete_into_block,
    post_block
  FROM
    citydb_pkg.create_ref_to_delete($1, $2);

  -- FOREIGN KEY which cover same columns as primary key
  post_block := post_block || citydb_pkg.create_ref_to_parent_delete($1, $2);

  -- putting all together
  IF pre_block = '' AND post_block = '' THEN
    ddl_command := ddl_command
      || E'\n  -- delete '||$1||'s'
      || delete_block || ';'
      || E'\n$body$'
      || E'\nLANGUAGE sql STRICT';
  ELSE
    ddl_command := ddl_command
      || declare_block
      || E'\nBEGIN'
      || pre_block
      || E'\n  -- delete '||$1||'s'
      || delete_block
      || delete_into_block
      || post_block
      || E'\n  RETURN deleted_id;'
      || E'\nEND;'
      || E'\n$body$'
      || E'\nLANGUAGE plpgsql STRICT';
  END IF;

  EXECUTE ddl_command;
END;
$$
LANGUAGE plpgsql STRICT;