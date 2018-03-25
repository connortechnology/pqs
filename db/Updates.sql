alter table tbl_orders add column shipping_type text;
alter table tbl_order_contents add column product int;
alter table tbl_orders add column shipping numeric(10,2);
alter table tbl_order_contents add column subgroup int;
alter table tbl_products  alter column kit set default false;
alter table tbl_order_contents  add column spec_pid int;



 update equipment_type_specification set dsc = name;
 insert into division values (1, 'default');
insert into price_indexes values ( 1, 'Products');

INSERT into equipment_type_specification (type,name,ranged,description,dsc ) VALUES ( 14, 'product_only',false,'Product Only','Product Only');

INSERT into equipment_type_specification (type,name,ranged,description,dsc ) VALUES ( 41, 'product_only',false,'Product Only','Product Only');

INSERT into equipment_type_specification (type,name,ranged,description,dsc ) VALUES ( 1, 'product_only',false,'Product Only','Product Only');
INSERT into equipment_type_specification (type,name,ranged,description,dsc ) VALUES ( 38, 'product_only',false,'Product Only','Product Only');
INSERT into equipment_type_specification (type,name,ranged,description,dsc ) VALUES ( 43, 'product_only',false,'Product Only','Product Only');

INSERT into equipment_type_specification (type,name,ranged,description,dsc ) VALUES ( 19, 'product_only',false,'Product Only','Product Only');


INSERT into tbl_equipment_specifications ( lngequipmentindex, strname, strvalue ) 
	select lngindex, 'product_only', 'N' FROM tbl_equipment where strtype in  ('press', 'web', 'digital', 'inkjet');


INSERT INTO categories VALUES (1, NULL, 'Stationery', 'Parent', true);
INSERT INTO categories VALUES (14, 1, 'Business Cards', 'Child', true);
INSERT INTO categories VALUES (15, 14, 'FULL Color', 'Child', true);
INSERT INTO categories VALUES (16, 14, 'FULL Color UV/AQ', 'Child', true);
INSERT INTO categories VALUES (9, 1, 'Letterhead', 'Child', true);
INSERT INTO categories VALUES (37, NULL, 'Wearables', 'Employees subcategory of Wearables', true);
INSERT INTO categories VALUES (17, 14, 'FULL Color UV/AQ Folded', 'Child', false);
INSERT INTO categories VALUES (18, 14, 'FULL Color Specialty', 'Child', false);


create table product_defaults ( 
	category int,
	name text,
    value text
);

create table product_options (
	product int,
	opt int
);


create sequence options_seq;
create sequence product_filter_seq;

CREATE TABLE options (
    id integer DEFAULT nextval('options_seq'::regclass) NOT NULL,
    filter integer,
    name text
);

CREATE TABLE product_filter (
    id integer DEFAULT nextval('product_filter_seq'::regclass) NOT NULL,
    category integer,
    name text
);

ALTER TABLE ONLY product_filter
    ADD CONSTRAINT product_filter_pkey PRIMARY KEY (id);


Alter table tbl_projects add column q2 int;
Alter table tbl_projects add column q3 int;
Alter table tbl_projects add column digifed bool;


create sequence eid_seq;
Alter table tbl_projects alter column eid SET DEFAULT nextval('eid_seq'::text);


 alter table tbl_products add column show_price bool;
 alter table tbl_products add column delivery_days int;

ALTER table tbl_projects ADD column files bool;
ALTER table tbl_order_contents ADD COLUMN hide bool;
ALTER table tbl_order_contents ADD COLUMN jobname text;

ALTER table tbl_orders ADD COLUMN paypal_token text;
ALTER table tbl_orders ADD COLUMN token_type text;


ALTER table tbl_project_contents ADD column custom_sort int;

CREATE TABLE product_discount ( 
	product int,
	min int,
	max int,
	discount int

);

Alter table tbl_quote_details add column product int;
Alter table tbl_quote_details add column label text;
Alter table tbl_products alter column weight type numeric(10,4);


-------UPDATES TO PQS-4.1 --------------
Alter table pricing_matrix alter column cost type numeric(10,4);
Alter table pricing_matrix alter column sell type numeric(10,4);



-------Hot Fix Updates 4.1 ------
Alter table categories add column description text;











-------- Start of No Bindery, Not Added to live db ----------

INSERT into tbl_equipment_type VALUES  ( 51, 'NoPrinting', 'No Printing');
INSERT into service_type_equipment VALUES ( 68, 1);
INSERT into tbl_equipment VALUES  ( 1, 'NoPrint', 'No Printing', Null, Null, Null, 'NoPrinting');

INSERT INTO project_type_by_press VALUES ( 51, 100);

drop trigger press_type on tbl_projects;

INSERT into project_type_group values ( 7, 'NoPrint');


UPDATE tbl_projecttypes set lnggroup = 7 where lngindex = 100;


INSERT INTO tbl_projecttypes VALUES (100, 'NoPrint', 'No Printing', 'prin/prin_noprint.html', '', 1, false, 1, 0.0, 0.0);
INSERT INTO project_type_by_press VALUES ( 41, 100);
INSERT INTO project_type_by_press VALUES ( 14, 100);


INSERT INTO tbl_configuration VALUES ( 'Default Product Category', 102);

update tbl_service_types set ysncreatevisible = 'Y' where strid = 'Cutting';




--Rest Product Prices
INSERT INTO pricing_matrix (index, item, min, max, cost, sell, pricelist)  (
        SELECT 1, id, NULL, NULL, 20, 30, 1 FROM tbl_products where strid ~ 'bc'
);

INSERT INTO pricing_matrix (index, item, min, max, cost, sell, pricelist)  (
        SELECT 1, id, NULL, NULL, 2, 3, 1 FROM tbl_products where strid ~ 'Mug'
);

 delete from tbl_configuration where strconfigtitle ~ 'paypal';


--Paypal Stuff --

INSERT INTO tbl_configuration VALUES ('paypal_user', 'apitest');
INSERT INTO tbl_configuration VALUES ('paypal_vendor', 'revshop');
INSERT INTO tbl_configuration VALUES ('paypal_mode', 'TEST');
INSERT INTO tbl_configuration VALUES ('paypal_password', 'thisnosp1');

INSERT INTO tbl_configuration VALUES ('paypal_user', 'KYWYTN02TA');
INSERT INTO tbl_configuration VALUES ('paypal_vendor', 'GY5MEIC0RQ');
INSERT INTO tbl_configuration VALUES ('paypal_mode', 'TEST');
INSERT INTO tbl_configuration VALUES ('paypal_password', 'CI3YOLP2Q2KFOY0V');

INSERT INTO tbl_configuration VALUES ('paypal_user', 'apiuser');
INSERT INTO tbl_configuration VALUES ('paypal_vendor', 'SherwoodPrinters');
INSERT INTO tbl_configuration VALUES ('paypal_mode', 'TEST');
INSERT INTO tbl_configuration VALUES ('paypal_password', 'NJ3YOLP2Q');
INSERT INTO tbl_configuration VALUES ('paypal_partner', 'PayPalCA');


