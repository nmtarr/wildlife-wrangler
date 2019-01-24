/*
Description: This code uses occurrence data collected with
'occurrence_records_summaries.py' to evaluate the GAP range map for a species.
A table is created for the GAP range and columns reporting the results of
evaluation and validation are populated after evaluating spatial relationships
of occurrence records (circles) and GAP range.

The results of this code are new columns in the GAP range table (in the db
created for work in this repository) and a range shapefile.

The primary use of code like this would be range evaluation and revision.

Unresolved issues:
1. How can overlap be handled?  As is, occurrence circles overlaping huc
   boundaries are omitted.  Set a tolerable level of spatial error?
2. Can the final shapefile be dissolved?
   Code to try:
   """Select f.field1 as field1, st_unaryunion(st_collect(f.geometry)) as geometry
   From tableA as f
   Group by field1;"""
3. Can the runtime be improved with spatial indexing?  Minimum bounding rectangle?
4. ".import" has to be worked around when this goes into python.
5. Locations of huc files.
6. Documenting evaluation parameters (spatial error allowed, spatial relationship
   rules.)
*/

.headers on
.mode csv
ATTACH DATABASE '/users/nmtarr/documents/ranges/outputs/bybcux0_occurrences.sqlite'
            AS occs;

ATTACH DATABASE '/users/nmtarr/documents/ranges/inputs/requests.sqlite' AS requests;

SELECT load_extension('mod_spatialite');

/*#############################################################################
                             Assess Agreement
 ############################################################################*/

/*#################  How many overlapping circles to attribute?
#############################################################*/
/*  Table of overlaping circles and hucs */
DROP TABLE green;

CREATE TABLE green AS
              SELECT shucs.HUC12RNG, ox.occ_id,
              CastToMultiPolygon(Intersection(shucs.geom_102008, ox.circle_albers))
                  AS geom_102008
              FROM shucs, occs.occurrences as ox
              WHERE Intersects(shucs.geom_102008, ox.circle_albers);

SELECT RecoverGeometryColumn('green', 'geom_102008', 102008, 'MULTIPOLYGON', 'XY');

/* Export maps */
SELECT ExportSHP('green', 'geom_102008',
                 '/users/nmtarr/documents/ranges/green',
                 'utf-8');

/* Get a table of huc12 codes with count of occurrence circles with
a suitable proportion (error tolerance) of the circle within the huc */
CREATE TABLE orange AS
  SELECT green.HUC12RNG, green.occ_id,
         100 * (Area(green.geom_102008) / Area(ox.circle_albers))
            AS proportion_circle
  FROM green
       LEFT JOIN occs.occurrences AS ox
       ON green.occ_id = ox.occ_id
  WHERE proportion_circle BETWEEN (100 - (SELECT error_tolerance
                                          FROM requests.species_concepts
                                          WHERE species_id = 'bybcux0'))
                                  AND 100;

/*  How many occurrences in each huc that had an occurrence? */
ALTER TABLE sp_range ADD COLUMN eval_gbif1_cnt INTEGER;

UPDATE sp_range
SET eval_gbif1_cnt = (SELECT COUNT(occ_id)
                      FROM orange
                      WHERE HUC12RNG = sp_range.strHUC12RNG
                      GROUP BY HUC12RNG);


/*  Find hucs that contained gbif occurrences, but were not in gaprange and
insert them into sp_range as new records */
INSERT INTO sp_range (strHUC12RNG, eval_gbif1_cnt)
            SELECT orange.HUC12RNG, COUNT(occ_id)
            FROM orange LEFT JOIN sp_range ON sp_range.strHUC12RNG = orange.HUC12RNG
            WHERE sp_range.strHUC12RNG IS NULL
            GROUP BY orange.HUC12RNG;







/*############################  Does HUC contain an occurrence?
#############################################################*/
ALTER TABLE sp_range ADD COLUMN eval_gbif1 INTEGER;

/*  Record in sp_range that gap and gbif agreed on species presence, in light
of the pad for the species. */
UPDATE sp_range
SET eval_gbif1 = 1
WHERE eval_gbif1_cnt >= (SELECT pad
                        FROM requests.species_concepts
                        WHERE species_id = 'bybcux0');


/*  For new records, put zeros in GAP range attribute fields  */
UPDATE sp_range
SET intGAPOrigin = 0,
    intGAPPresence = 0,
    intGAPReproduction = 0,
    intGAPSeason = 0,
    eval_gbif1 = 0
WHERE eval_gbif1_cnt >= 0 AND intGAPOrigin IS NULL;


/*###########################################  Validaton column
#############################################################*/
/*  Populate a validation column.  If an evaluation supports the GAP ranges
then it is validated */
ALTER TABLE sp_range ADD COLUMN validated_presence INTEGER NOT NULL DEFAULT 0;

UPDATE sp_range
SET validated_presence = 1
WHERE eval_gbif1 = 1;


/*#############################################################################
                               Export Table and Map
 ############################################################################*/
/*  Create a version of sp_range with geometry  */
CREATE TABLE sp_geom AS
              SELECT sp_range.*, shucs.geom_102008
              FROM sp_range LEFT JOIN shucs ON sp_range.strHUC12RNG = shucs.HUC12RNG;
SELECT RecoverGeometryColumn('sp_geom', 'geom_102008', 102008, 'POLYGON');

/* Export maps */
SELECT ExportSHP('sp_geom', 'geom_102008',
                 '/users/nmtarr/documents/ranges/bYBCUx_CONUS_Range_2001v1_eval2',
                 'utf-8');

/* Export csv */
.output /users/nmtarr/documents/ranges/bYBCUx_CONUS_Range_2001v1_eval.csv
SELECT * FROM sp_range;