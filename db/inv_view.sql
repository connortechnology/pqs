DROP view mat_inventory;

Create View mat_inventory AS

select 'stock' as itype, strid as id, 
strname || ' ' || strfinish || ' ' || strcolour || ' ' ||  strweight || ' ' || dblwidth || 'x'|| dblheight as name
FROM tbl_paper
Union

Select 'product', strid, name from tbl_products;

DROP table inventory_count;
Create table inventory_count (
	id text,
	onhand int default 0,
	onorder int default 0
);

INSERT INTO inventory_count (SELECT id FROM mat_inventory );

DROP table inventory_filters;
create table inventory_filters (
	id int,
	itype text,
	itable text,
	field text,
	label text,
	ftype text,
	option_sql text
);

DELETE FROM inventory_filters;
INSERT INTO inventory_filters values ( 1, 'product', 'tbl_products', 'category', 'Category', 'select', 'SELECT id, name FROM categories ORDER by name');
INSERT INTO inventory_filters values ( 2, 'stock', 'tbl_paper', 'strcategory', 'Category', 'select', 'SELECT DISTINCT strcategory, strcategory FROM tbl_paper ORDER by 2');

ALTER table tbl_project_contents add column stock int;
ALTER table tbl_project_contents add column gross_sheets  int;


drop table project_data;
create table project_data ( pid int, userid int, note text, notedate timestamp);

