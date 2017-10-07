WITH RECURSIVE tree AS (
    SELECT cc.id as SubTreeRoot,
            cc.id 
            FROM categories cc
UNION ALL
    SELECT cst.SubTreeRoot, cc.id
        FROM categories cc
        INNER JOIN tree cst ON cst.id = cc.parent
)
SELECT cst.id
FROM tree cst
WHERE cst.SubTreeRoot = 10
