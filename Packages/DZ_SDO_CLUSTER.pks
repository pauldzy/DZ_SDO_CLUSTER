CREATE OR REPLACE PACKAGE dz_sdo_cluster
AUTHID CURRENT_USER
AS
   
   -----------------------------------------------------------------------------
   -----------------------------------------------------------------------------
   /*
   Function: update_metadata_envelope

   Procedure to update user_sdo_geom_metadata table with extents of the current
   set of geometry.

   Parameters:

      p_table_name - the table to examine
      p_column_name - the spatial column in the table to examine

   Returns:

      NA
      
   Notes:
   
   -  To avoid tracking dimension name, SRIDs and dimensions beyond X and Y 
      this procedure requires the metadata record to already exist.
      
   -  Any M or Z dimensions are ignored and will remain as is.

   */
   PROCEDURE update_metadata_envelope(
       p_table_name       IN  VARCHAR2
      ,p_column_name      IN  VARCHAR2 DEFAULT 'SHAPE'
   );
   
   -----------------------------------------------------------------------------
   -----------------------------------------------------------------------------
   /*
   Function: morton

   Morton Key generator function by Simon Greener   
   http://www.spatialdbadvisor.com/oracle_spatial_tips_tricks/138/spatial-sorting-of-data-via-morton-key

   Parameters:

      p_column - the morton grid column number
      p_row - the morton grid row number

   Returns:

      INTEGER

   */
   FUNCTION morton(
       p_column           IN  NATURAL
      ,p_row              IN  NATURAL
   ) RETURN INTEGER DETERMINISTIC;
   
   -----------------------------------------------------------------------------
   -----------------------------------------------------------------------------
   /*
   Function: morton_key

   Wrapper function to handle the conversion of geometry types into points 
   before generating the morton key.

   Parameters:

      p_input - input geometry to generate a morton key for.
      p_x_offset - the offset to move x coordinates to be zero-based
      p_y_offset - the offset to move y coordinates to be zero-based
      p_x_divisor - the grid divisor for the x axis
      p_y_divisor - the grid divisor for the y axis
      p_geom_devolve - either ACCURATE or FAST to control how points are generated.
      p_tolerance - tolerance value to use when generating centroids and such.
      
   Returns:

      INTEGER
      
   Notes:
   
   -  for p_geom_devolve with polygon input, ACCURATE uses SDO_CENTROID while
      FAST uses SDO_POINTONSURFACE.
      
   -  for p_geom_devolve with linear or multipoint input, ACCURATE uses the 
      SDO_CENTROID of the geometry MBR while FAST uses the first point in the 
      geometry.

   */
   FUNCTION morton_key(
       p_input            IN  MDSYS.SDO_GEOMETRY
      ,p_x_offset         IN  NUMBER
      ,p_y_offset         IN  NUMBER
      ,p_x_divisor        IN  NUMBER
      ,p_y_divisor        IN  NUMBER
      ,p_geom_devolve     IN  VARCHAR2 DEFAULT 'ACCURATE'
      ,p_tolerance        IN  NUMBER DEFAULT 0.05
   ) RETURN INTEGER DETERMINISTIC;
   
   -----------------------------------------------------------------------------
   -----------------------------------------------------------------------------
   /*
   Function: morton_update

   Function to generate the morton key update clause.

   Parameters:

      p_owner - the owner of the table to examine
      p_table_name - the table to examine
      p_column_name - the spatial column in the table to examine
      p_use_metadata_env - TRUE/FALSE whether to obtain envelope from metadata
      p_grid_size - the desired morton grid size

   Returns:

      VARCHAR2
      
   Notes:
   
   -  p_use_metadata_env value of TRUE will obtains envelope size from metadata.
      FALSE will calculate the values from the table via SDO_AGGR_MBR (and may 
      take a long time).
      
   -  Probably the most important value here is the grid size.  You should use
      a reasonable grid size.

   */
   FUNCTION morton_update(
       p_owner            IN  VARCHAR2 DEFAULT NULL
      ,p_table_name       IN  VARCHAR2
      ,p_column_name      IN  VARCHAR2 DEFAULT 'SHAPE'
      ,p_use_metadata_env IN  VARCHAR2 DEFAULT 'FALSE'
      ,p_grid_size        IN  NUMBER
   ) RETURN VARCHAR2;
   
   -----------------------------------------------------------------------------
   -----------------------------------------------------------------------------
   /*
   Function: morton_visualize

   Function to visualize the results of a morton key spatial clustering.  
   Intended for use with mapviewer or other sdo_geometry viewers that can directly
   display the result of a query.

   Parameters:

      p_owner - the owner of the table to examine
      p_table_name - the table to examine
      p_column_name - the spatial column in the table to examine
      p_key_field - the field name used to obtain the start record
      p_key_start - the field value used to obtain the start record
      p_morton_key_range - the range of morton values to fetch results for
      p_morton_key_field - the name of the field holding the morton key
      
   Returns:

      MDSYS.SDO_GEOMETRY
      
   Notes:
   
   -  Use a modest morton key range to avoid an overly large return geometry.
   
   -  You may wish to index the morton key field for performance when running 
      this function.

   */
   FUNCTION morton_visualize(
       p_owner            IN  VARCHAR2 DEFAULT NULL
      ,p_table_name       IN  VARCHAR2
      ,p_column_name      IN  VARCHAR2 DEFAULT 'SHAPE'
      ,p_key_field        IN  VARCHAR2 DEFAULT 'OBJECTID'
      ,p_key_start        IN  VARCHAR2
      ,p_morton_key_range IN  NUMBER
      ,p_morton_key_field IN  VARCHAR2 DEFAULT 'MORTON_KEY'
   ) RETURN MDSYS.SDO_GEOMETRY;
   
END dz_sdo_cluster;
/

GRANT EXECUTE ON dz_sdo_cluster TO public;

