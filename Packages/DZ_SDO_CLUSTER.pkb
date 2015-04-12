CREATE OR REPLACE PACKAGE BODY dz_sdo_cluster 
AS

   -----------------------------------------------------------------------------
   -----------------------------------------------------------------------------
   FUNCTION devolve_point(
       p_input            IN  MDSYS.SDO_GEOMETRY
      ,p_geom_devolve     IN  VARCHAR2 DEFAULT 'ACCURATE'
      ,p_tolerance        IN  NUMBER DEFAULT 0.05
   ) RETURN MDSYS.SDO_GEOMETRY
   AS
      sdo_output MDSYS.SDO_GEOMETRY;
      
   BEGIN
   
      IF p_input.get_gtype() IN (3,7)
      AND p_geom_devolve = 'ACCURATE'
      THEN
         sdo_output := MDSYS.SDO_GEOM.SDO_CENTROID(
             p_input
            ,p_tolerance
         );
         
      ELSIF p_input.get_gtype() IN (3,7)
      AND p_geom_devolve = 'FAST'
      THEN
         sdo_output := MDSYS.SDO_GEOM.SDO_POINTONSURFACE(
             p_input
            ,p_tolerance
         );
         
      ELSIF p_input.get_gtype() IN (2,4,5,6)
      AND p_geom_devolve = 'ACCURATE'
      THEN
         sdo_output := MDSYS.SDO_GEOM.SDO_CENTROID(
             MDSYS.SDO_GEOM.SDO_MBR(p_input)
            ,p_tolerance
         );
         
         IF sdo_output IS NULL
         THEN
             sdo_output := MDSYS.SDO_GEOMETRY(
                2001
               ,p_input.SDO_SRID
               ,MDSYS.SDO_POINT_TYPE(
                    p_input.SDO_ORDINATES(1)
                   ,p_input.SDO_ORDINATES(2)
                   ,NULL
                )
               ,NULL
               ,NULL
            );
            
         END IF;
      
      ELSIF p_input.get_gtype() IN (2,4,5,6)
      AND p_geom_devolve = 'FAST'
      THEN
         sdo_output := MDSYS.SDO_GEOMETRY(
             2001
            ,p_input.SDO_SRID
            ,MDSYS.SDO_POINT_TYPE(
                 p_input.SDO_ORDINATES(1)
                ,p_input.SDO_ORDINATES(2)
                ,NULL
             )
            ,NULL
            ,NULL
         );
         
      ELSIF p_input.get_gtype() = 1
      THEN
         IF p_input.SDO_POINT IS NULL
         THEN
            sdo_output := MDSYS.SDO_GEOMETRY(
                2001
               ,p_input.SDO_SRID
               ,MDSYS.SDO_POINT_TYPE(
                    p_input.SDO_ORDINATES(1)
                   ,p_input.SDO_ORDINATES(2)
                   ,NULL
                )
               ,NULL
               ,NULL
            );
         
         ELSE
            sdo_output := p_input;
            
         END IF;
      
      ELSE
         RAISE_APPLICATION_ERROR(-20001,'err');
         
      END IF;
      raise_application_error(-20001,sdo_output.sdo_point.X || ' ' || sdo_output.sdo_point.Y);
      RETURN sdo_output;
   
   END devolve_point;

   -----------------------------------------------------------------------------
   -----------------------------------------------------------------------------
   PROCEDURE update_metadata_envelope(
       p_table_name       IN  VARCHAR2
      ,p_column_name      IN  VARCHAR2 DEFAULT 'SHAPE'
   )
   AS
      str_column_name VARCHAR2(30 Char) := p_column_name;
      str_sql         VARCHAR2(4000 Char);
      num_check       NUMBER;
      sdo_envelope    MDSYS.SDO_GEOMETRY;
      obj_diminfo     MDSYS.SDO_DIM_ARRAY;
      
   BEGIN
   
      --------------------------------------------------------------------------
      -- Step 10
      -- Check over incoming parameters
      --------------------------------------------------------------------------
      IF str_column_name IS NULL
      THEN
         str_column_name := 'SHAPE';
         
      END IF;
      
      --------------------------------------------------------------------------
      -- Step 20
      -- Check that table and column exists
      --------------------------------------------------------------------------
      SELECT
      COUNT(*)
      INTO num_check
      FROM
      user_tables a
      JOIN
      user_tab_cols b
      ON
      a.table_name = b.table_name
      WHERE
          a.table_name = p_table_name
      AND b.column_name = str_column_name;
      
      IF num_check <> 1
      THEN
         RAISE_APPLICATION_ERROR(-20001,'cannot find user table with column name');
         
      END IF;
      
      --------------------------------------------------------------------------
      -- Step 30
      -- Check that metadata already exists
      --------------------------------------------------------------------------
      SELECT
      COUNT(*) 
      INTO num_check
      FROM
      user_sdo_geom_metadata a
      WHERE
          a.table_name = p_table_name
      AND a.column_name = str_column_name;
      
      IF num_check <> 1
      THEN
         RAISE_APPLICATION_ERROR(-20001,'no existing sdo metadata for table');
         
      END IF;
      
      SELECT
      a.diminfo
      INTO obj_diminfo
      FROM
      user_sdo_geom_metadata a
      WHERE
          a.table_name = p_table_name
      AND a.column_name = str_column_name;
      
      --------------------------------------------------------------------------
      -- Step 40
      -- Collect the aggregate mbr of the table
      --------------------------------------------------------------------------
      str_sql := 'SELECT '
              || 'MDSYS.SDO_AGGR_MBR(a.' || str_column_name || ') '
              || 'FROM '
              || p_table_name || ' a ';
              
      EXECUTE IMMEDIATE str_sql INTO sdo_envelope;
      
      --------------------------------------------------------------------------
      -- Step 50
      -- Update just the x and y elements of the diminfo object
      --------------------------------------------------------------------------
      obj_diminfo(1) := MDSYS.SDO_DIM_ELEMENT(
          obj_diminfo(1).sdo_dimname
         ,sdo_envelope.SDO_ORDINATES(1)
         ,sdo_envelope.SDO_ORDINATES(3)
         ,obj_diminfo(1).sdo_tolerance
      );
      
      obj_diminfo(2) := MDSYS.SDO_DIM_ELEMENT(
          obj_diminfo(2).sdo_dimname
         ,sdo_envelope.SDO_ORDINATES(2)
         ,sdo_envelope.SDO_ORDINATES(4)
         ,obj_diminfo(2).sdo_tolerance
      );
      
      --------------------------------------------------------------------------
      -- Step 60
      -- Update the metadata
      --------------------------------------------------------------------------
      UPDATE user_sdo_geom_metadata a
      SET a.diminfo = obj_diminfo 
      WHERE
          a.table_name = p_table_name
      AND a.column_name = str_column_name;
      
      COMMIT;
   
   END update_metadata_envelope;
   
   -----------------------------------------------------------------------------
   -----------------------------------------------------------------------------
   -- Function by Simon Greener
   -- http://www.spatialdbadvisor.com/oracle_spatial_tips_tricks/138/spatial-sorting-of-data-via-morton-key
   FUNCTION morton(
       p_column           IN  NATURAL
      ,p_row              IN  NATURAL
   ) RETURN INTEGER DETERMINISTIC
   AS
      v_row       NATURAL := ABS(p_row);
      v_col       NATURAL := ABS(p_column);
      v_key       NATURAL := 0;
      v_level     BINARY_INTEGER := 0;
      v_left_bit  BINARY_INTEGER;
      v_right_bit BINARY_INTEGER;
      v_quadrant  BINARY_INTEGER;
    
      FUNCTION left_shift(
          p_val   IN  NATURAL
         ,p_shift IN  NATURAL
      ) RETURN PLS_INTEGER
      AS
      BEGIN
         RETURN TRUNC(p_val * POWER(2,p_shift));
      
      END left_shift;
       
   BEGIN
      WHILE v_row > 0 OR v_col > 0 
      LOOP
         /*   split off the row (left_bit) and column (right_bit) bits and
              then combine them to form a bit-pair representing the
              quadrant                                                  */
         v_left_bit  := MOD(v_row,2);
         v_right_bit := MOD(v_col,2);
         v_quadrant  := v_right_bit + (2 * v_left_bit);
         v_key       := v_key + left_shift(v_quadrant,( 2 * v_level));
         /*   row, column, and level are then modified before the loop
              continues                                                */
         v_row := TRUNC(v_row / 2);
         v_col := TRUNC(v_col / 2);
         v_level := v_level + 1;
        
      END LOOP;
      
      RETURN v_key;
   
   END morton;
   
   -----------------------------------------------------------------------------
   -----------------------------------------------------------------------------
   FUNCTION morton_key(
       p_input            IN  MDSYS.SDO_GEOMETRY
      ,p_x_offset         IN  NUMBER
      ,p_y_offset         IN  NUMBER
      ,p_x_divisor        IN  NUMBER
      ,p_y_divisor        IN  NUMBER
      ,p_geom_devolve     IN  VARCHAR2 DEFAULT 'ACCURATE'
      ,p_tolerance        IN  NUMBER DEFAULT 0.05
   ) RETURN INTEGER DETERMINISTIC
   AS
      sdo_input        MDSYS.SDO_GEOMETRY := p_input;
      str_geom_devolve VARCHAR2(4000 Char) := UPPER(p_geom_devolve);
      num_tolerance    NUMBER := p_tolerance;
      
   BEGIN
   
      --------------------------------------------------------------------------
      -- Step 10
      -- Check over incoming parameters
      --------------------------------------------------------------------------
      IF str_geom_devolve IS NULL
      OR str_geom_devolve NOT IN ('ACCURATE','FAST')
      THEN
         str_geom_devolve := 'ACCURATE';
         
      END IF;
      
      IF num_tolerance IS NULL
      THEN
         num_tolerance := 0.05;
         
      END IF;
      
      --------------------------------------------------------------------------
      -- Step 20
      -- Devolve the input geometry to a point
      --------------------------------------------------------------------------
      sdo_input := devolve_point(
          p_input        => sdo_input
         ,p_geom_devolve => str_geom_devolve
         ,p_tolerance    => num_tolerance
      );
      
      --------------------------------------------------------------------------
      -- Step 30
      -- Return the Morton key
      --------------------------------------------------------------------------
      RETURN morton(
          FLOOR((sdo_input.SDO_POINT.y + p_y_offset ) / p_y_divisor )
         ,FLOOR((sdo_input.SDO_POINT.x + p_x_offset ) / p_x_divisor )
      );
   
   END morton_key;
   
   -----------------------------------------------------------------------------
   -----------------------------------------------------------------------------
   FUNCTION morton_update(
       p_owner            IN  VARCHAR2 DEFAULT NULL
      ,p_table_name       IN  VARCHAR2
      ,p_column_name      IN  VARCHAR2 DEFAULT 'SHAPE'
      ,p_use_metadata_env IN  VARCHAR2 DEFAULT 'FALSE'
      ,p_grid_size        IN  NUMBER
   ) RETURN VARCHAR2
   AS
      str_owner       VARCHAR2(30 Char) := p_owner;
      str_column_name VARCHAR2(30 Char) := p_column_name;
      str_use_metadata_env VARCHAR2(4000 Char) := UPPER(p_use_metadata_env);
      str_sql         VARCHAR2(4000 Char);
      sdo_envelope    MDSYS.SDO_GEOMETRY;
      obj_diminfo     MDSYS.SDO_DIM_ARRAY;
      num_check       NUMBER;
      num_max_x       NUMBER;
      num_min_x       NUMBER;
      num_max_y       NUMBER;
      num_min_y       NUMBER;
      num_range_x     NUMBER;
      num_range_y     NUMBER;
      num_offset_x    NUMBER;
      num_offset_y    NUMBER;
      num_divisor_x   NUMBER;
      num_divisor_y   NUMBER;
      
   BEGIN
   
      --------------------------------------------------------------------------
      -- Step 10
      -- Check over incoming parameters
      --------------------------------------------------------------------------
      IF str_owner IS NULL
      THEN
         str_owner := USER;
         
      END IF;
      
      IF str_column_name IS NULL
      THEN
         str_column_name := 'SHAPE';
         
      END IF;
      
      IF str_use_metadata_env IS NULL
      OR str_use_metadata_env NOT IN ('TRUE','FALSE')
      THEN
         str_use_metadata_env := 'FALSE';
      
      END IF;
      
      --------------------------------------------------------------------------
      -- Step 20
      -- Check that table and column exists
      --------------------------------------------------------------------------
      SELECT
      COUNT(*)
      INTO num_check
      FROM
      all_tables a
      JOIN
      all_tab_cols b
      ON
          a.owner = b.owner
      AND a.table_name = b.table_name
      WHERE
          a.owner = str_owner
      AND a.table_name = p_table_name
      AND b.column_name = str_column_name;
      
      IF num_check <> 1
      THEN
         RAISE_APPLICATION_ERROR(-20001,'cannot find table with column name');
         
      END IF;
      
      --------------------------------------------------------------------------
      -- Step 30
      -- Get the max and mins either from metadata or calc it
      --------------------------------------------------------------------------
      IF str_use_metadata_env = 'TRUE'
      THEN
         SELECT
         COUNT(*) 
         INTO num_check
         FROM
         user_sdo_geom_metadata a
         WHERE
             a.table_name = p_table_name
         AND a.column_name = str_column_name;
         
         IF num_check <> 1
         THEN
            RAISE_APPLICATION_ERROR(-20001,'no existing sdo metadata for table');
            
         END IF;
         
         SELECT
         a.diminfo
         INTO obj_diminfo
         FROM
         user_sdo_geom_metadata a
         WHERE
             a.table_name = p_table_name
         AND a.column_name = str_column_name;
      
         num_min_x := obj_diminfo(1).sdo_lb;
         num_max_x := obj_diminfo(1).sdo_ub;
         
         num_min_y := obj_diminfo(2).sdo_lb;
         num_max_y := obj_diminfo(2).sdo_ub;
         
      ELSE
         str_sql := 'SELECT '
                 || 'MDSYS.SDO_AGGR_MBR(a.' || str_column_name || ') '
                 || 'FROM '
                 || p_table_name || ' a ';
              
         EXECUTE IMMEDIATE str_sql INTO sdo_envelope;
         
         num_min_x := sdo_envelope.SDO_ORDINATES(1);
         num_max_x := sdo_envelope.SDO_ORDINATES(3);
         
         num_min_y := sdo_envelope.SDO_ORDINATES(2);
         num_max_y := sdo_envelope.SDO_ORDINATES(4);
      
      END IF;
      
      --------------------------------------------------------------------------
      -- Step 40
      -- Get the max and mins either from metadata or calc it
      --------------------------------------------------------------------------
      num_range_x   := num_max_x - num_min_x;
      num_range_y   := num_max_y - num_min_y;
      num_offset_x  := num_min_x * -1;
      num_offset_y  := num_min_y * -1;
      num_divisor_x := num_range_x / p_grid_size;
      num_divisor_y := num_range_y / p_grid_size;
      
      --------------------------------------------------------------------------
      -- Step 50
      -- Return the update statement
      --------------------------------------------------------------------------
      RETURN 'morton_key(' || 
         str_column_name || ',' ||
         num_offset_x || ',' || num_offset_y || ',' ||
         num_divisor_x || ',' || num_divisor_y || ')';
   
   END morton_update;
   
   -----------------------------------------------------------------------------
   -----------------------------------------------------------------------------
   FUNCTION morton_visualize(
       p_owner            IN  VARCHAR2 DEFAULT NULL
      ,p_table_name       IN  VARCHAR2
      ,p_column_name      IN  VARCHAR2 DEFAULT 'SHAPE'
      ,p_key_field        IN  VARCHAR2 DEFAULT 'OBJECTID'
      ,p_key_start        IN  VARCHAR2
      ,p_morton_key_range IN  NUMBER
      ,p_morton_key_field IN  VARCHAR2 DEFAULT 'MORTON_KEY'
   ) RETURN MDSYS.SDO_GEOMETRY
   AS
      str_sql     VARCHAR2(4000 Char);
      str_owner   VARCHAR2(30 Char) := p_owner;
      int_morton  INTEGER;
      ary_sdo     MDSYS.SDO_GEOMETRY_ARRAY;
      sdo_temp    MDSYS.SDO_GEOMETRY;
      sdo_output  MDSYS.SDO_GEOMETRY;
      int_counter PLS_INTEGER;
      
   BEGIN
   
      --------------------------------------------------------------------------
      -- Step 10
      -- Check over incoming parameters
      --------------------------------------------------------------------------
      IF str_owner IS NULL
      THEN
         str_owner := USER;
         
      END IF;
      
      --------------------------------------------------------------------------
      -- Step 20
      -- Grab the intial morton key for start record
      --------------------------------------------------------------------------
      str_sql := 'SELECT '
              || 'a.' || p_morton_key_field || ' ' 
              || 'FROM '
              || str_owner || '.' || p_table_name || ' a ' 
              || 'WHERE '
              || '    a.' || p_key_field || ' = :p01 '
              || 'AND rownum <= 1';
      
      EXECUTE IMMEDIATE str_sql INTO int_morton
      USING p_key_start;
      
      --------------------------------------------------------------------------
      -- Step 30
      -- Grab the geometries that follow 
      --------------------------------------------------------------------------
      str_sql := 'SELECT '
              || 'a.' || p_column_name || ' '
              || 'FROM '
              || str_owner || '.' || p_table_name || ' a ' 
              || 'WHERE '
              || '    a.' || p_morton_key_field || ' >= :p01 '
              || 'AND a.' || p_morton_key_field || ' <  :p02 '
              || 'ORDER BY '
              || 'a.' || p_morton_key_field || ' ASC ';
              
      EXECUTE IMMEDIATE str_sql
      BULK COLLECT INTO ary_sdo
      USING int_morton, int_morton + p_morton_key_range;
      
      IF ary_sdo IS NULL
      OR ary_sdo.COUNT = 0
      THEN
         RETURN NULL;
         
      END IF;

      --------------------------------------------------------------------------
      -- Step 40
      -- Construct the line
      --------------------------------------------------------------------------
      sdo_output := MDSYS.SDO_GEOMETRY(
          2002
         ,ary_sdo(1).SDO_SRID
         ,NULL
         ,MDSYS.SDO_ELEM_INFO_ARRAY(1,2,1)
         ,MDSYS.SDO_ORDINATE_ARRAY()
      );
      
      int_counter := 1;
      sdo_output.SDO_ORDINATES.EXTEND(ary_sdo.COUNT * 2);
      FOR i IN 1 .. ary_sdo.COUNT
      LOOP
         sdo_temp := devolve_point(ary_sdo(i),'ACCURATE',1);
         sdo_output.SDO_ORDINATES(int_counter) := sdo_temp.SDO_POINT.X;
         int_counter := int_counter + 1;
         sdo_output.SDO_ORDINATES(int_counter) := sdo_temp.SDO_POINT.Y;
         int_counter := int_counter + 1;
         
      END LOOP;
      
      --------------------------------------------------------------------------
      -- Step 50
      -- Return what we gots
      --------------------------------------------------------------------------
      RETURN sdo_output;
   
   END morton_visualize;
      
END dz_sdo_cluster;
/

