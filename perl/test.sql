;WITH RECURSIVE items AS (
  SELECT id 
  , 0 AS Level
  , CAST(id AS VARCHAR(255)) AS Path
  FROM categories WHERE parent IS NULL
  UNION ALL
  SELECT i.id
  , Level + 1
  , CAST(Path || ',' || CAST(i.id AS VARCHAR(255)) AS VARCHAR(255)) AS Path
  FROM categories i
  INNER JOIN items itms ON itms.id = i.parent
  )

SELECT * FROM items  ORDER BY Path;
