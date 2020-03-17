-- 3D City Database - The Open Source CityGML Database
-- http://www.3dcitydb.org/
--
-- Copyright 2013 - 2020
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

\pset footer off
SET client_min_messages TO WARNING;
\set ON_ERROR_STOP ON

\set SRSNO :srsno
\set GMLSRSNAME :gmlsrsname

--// check if the PostGIS extension is available
--// check if version is below 3 or if postgis_raster extension is available
SELECT postgis_lib_version() AS postgis_version \gset
SELECT EXISTS(SELECT 1 AS create_raster FROM pg_available_extensions WHERE name = 'postgis_raster') AS postgis3_raster \gset

--// create schema
CREATE SCHEMA citydb;

--// set search_path for this session
SELECT current_setting('search_path') AS current_path \gset
SET search_path TO citydb, :current_path;

--// create TABLES, SEQUENCES, CONSTRAINTS, INDEXES
\echo
\echo 'Setting up database schema of 3DCityDB instance ...'
\i SCHEMA/SCHEMA.sql

--// fill tables OBJECTCLASS
\i SCHEMA/OBJECTCLASS/OBJECTCLASS_INSTANCES.sql
\i SCHEMA/OBJECTCLASS/AGGREGATION_INFO_INSTANCES.sql

--// create schema FUNCTIONS
\i SCHEMA/OBJECTCLASS/OBJCLASS.sql
\i SCHEMA/ENVELOPE/ENVELOPE.sql
\i SCHEMA/DELETE/DELETE.sql

--// create additional schema for raster data only if raster type is installed
SELECT CASE WHEN :'postgis_version' < '3' OR :'postgis3_raster' = 't'
  THEN 'CREATE_DB_RASTER.sql'
  ELSE 'SCHEMA/RASTER/DO_NOTHING.sql'
  END AS create_raster;
\gset

\i :create_raster

--// create CITYDB_PKG (additional schema with PL/pgSQL-Functions)
\echo
\echo 'Creating additional schema ''citydb_pkg'' ...'
CREATE SCHEMA citydb_pkg;

\i CITYDB_PKG/TYPES/TYPES.sql
\i CITYDB_PKG/UTIL/UTIL.sql
\i CITYDB_PKG/CONSTRAINT/CONSTRAINT.sql
\i CITYDB_PKG/INDEX/IDX.sql
\i CITYDB_PKG/SRS/SRS.sql
\i CITYDB_PKG/STATISTICS/STAT.sql

--// create and fill INDEX_TABLE
\i SCHEMA/INDEX_TABLE/INDEX_TABLE.sql

--// update search_path on database level
ALTER DATABASE :"DBNAME" SET search_path TO citydb, citydb_pkg, :current_path;

\echo
\echo '3DCityDB creation complete!'

--// checks if the chosen SRID is provided by the spatial_ref_sys table
\echo
\echo 'Checking spatial reference system ...'
SELECT citydb_pkg.check_srid(:SRSNO);

\echo 'Setting spatial reference system of 3DCityDB instance ...'
INSERT INTO citydb.DATABASE_SRS(SRID,GML_SRS_NAME) VALUES (0,'init');
SELECT citydb_pkg.change_schema_srid(:SRSNO,:'GMLSRSNAME');
\echo 'Done'
