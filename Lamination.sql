insert into tbl_service_types (strid,strname,strtype,strurl,strcategory,ysncreatevisible,ysnviewvisible)
values ('Laminating','LAMINATING','Lamination','spec/Lamination.html', 'Finishing','Y','Y');

insert into service_type_by_project_group values (1, (SELECT lngindex from tbl_service_types where strid='Laminating'));
insert into service_type_by_project_group values (2, (SELECT lngindex from tbl_service_types where strid='Laminating'));
insert into service_type_by_project_group values (7, (SELECT lngindex from tbl_service_types where strid='Laminating'));

insert into tbl_equipment (strid, strname, strdescription,strcategory) values
('Laminator - Matrix','Laminator - Matrix','Laminator - Matrix','Finishing');
insert into tbl_equipment (strid, strname, strdescription, strcategory) values
('Laminator - Wesco','Laminator - Wesco','Laminator - Wesco','Finishing');
insert into tbl_equipment (strid, strname, strdescription, strcategory) values
('Laminator - GBC Voyager','Laminator - GBC Voyager','Laminator - GBC Voyager 30"','Finishing');

select setval('tbl_services_lngindex_seq', (SELECT MAX(lngindex) FROM tbl_services));

insert into tbl_services (strid, strname, strdescription, lngcategoryindex,lngtype) values
('Lamination','Lamination','Lamination',
  (SELECT lngindex from tbl_service_categories where strname='Finishing'),
  (SELECT lngindex from tbl_service_types WHERE strid='Laminating')
);

insert into tbl_services (strid, strname, strdescription,lngcategoryindex, lngtype) values
('LaminationMakeReady','LaminationMakeReady', 'Lamination Make Ready',
  (SELECT lngindex from tbl_SErvice_categories where strname='Finishing'),
  (SELECT lngindex from tbl_service_types WHERE strid='Laminating')
);

INSERT into tbl_service_prices (lnglistindex,lngserviceindex,lngequipmentindex,dblcost,dblmarkup,dblprice,strunits,ysndiscountable) values
(1, (SELECT lngindex from tbl_services where strname='Lamination'),(select lngindex from tbl_equipment where strname='Laminator - Matrix'),
  0.01,0.00,0.01,'per inch','Y');
INSERT into tbl_service_prices (lnglistindex,lngserviceindex,lngequipmentindex,dblcost,dblmarkup,dblprice,strunits,ysndiscountable) values
(1, (SELECT lngindex from tbl_services where strname='LaminationMakeReady'),(select lngindex from tbl_equipment where strname='Laminator - Matrix'),
  50,0.00,50,'','Y');

INSERT into tbl_service_prices (lnglistindex,lngserviceindex,lngequipmentindex,dblcost,dblmarkup,dblprice,strunits,ysndiscountable) values
(1, (SELECT lngindex from tbl_services where strname='Lamination'),(select lngindex from tbl_equipment where strname='Laminator - Wesco'),
  0.01,0.00,0.01,'per inch','Y');
INSERT into tbl_service_prices (lnglistindex,lngserviceindex,lngequipmentindex,dblcost,dblmarkup,dblprice,strunits,ysndiscountable) values
(1, (SELECT lngindex from tbl_services where strname='LaminationMakeReady'),(select lngindex from tbl_equipment where strname='Laminator - Wesco'),
  50,0.00,50,'','Y');

INSERT into tbl_service_prices (lnglistindex,lngserviceindex,lngequipmentindex,dblcost,dblmarkup,dblprice,strunits,ysndiscountable) values
(1, (SELECT lngindex from tbl_services where strname='Lamination'),(select lngindex from tbl_equipment where strname='Laminator - GBC Voyager'),
  0.01,0.00,0.01,'per inch','Y');
INSERT into tbl_service_prices (lnglistindex,lngserviceindex,lngequipmentindex,dblcost,dblmarkup,dblprice,strunits,ysndiscountable) values
(1, (SELECT lngindex from tbl_services where strname='LaminationMakeReady'),(select lngindex from tbl_equipment where strname='Laminator - GBC Voyager'),
  50,0.00,50,'','Y');


INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Matrix'), 'Laminating Capable', 'Y');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Matrix'), 'Laminating Sides', 'Single');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Matrix'), 'Laminating Style', 'Sheet');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue,strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Matrix'), 'Laminate Width', '19.5', 'Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue,strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Matrix'), 'Laminating Count', 'Net Sheets', '');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue,strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Matrix'), 'Laminating Waste', '10', 'Percent');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Matrix'), 'Maximum Calliper', '0.024','Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Matrix'), 'Minimum Calliper', '0.008','Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Matrix'), 'Maximum Sheet Length', '26','Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Matrix'), 'Maximum Sheet Width', '20','Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Matrix'), 'Run Speed', '23760','inches per hour');

INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Wesco'), 'Laminating Capable', 'Y');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Wesco'), 'Laminating Sides', 'Single');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Wesco'), 'Laminating Style', 'Sheet');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue,strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Wesco'), 'Laminate Width', '19.5', 'Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue,strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Wesco'), 'Laminating Count', 'Net Sheets', '');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue,strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Wesco'), 'Laminating Waste', '10', 'Percent');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Wesco'), 'Maximum Calliper', '0.024','Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Wesco'), 'Minimum Calliper', '0.008','Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Wesco'), 'Minimum Sheet Length', '18','Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Wesco'), 'Minimum Sheet Width', '12','Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Wesco'), 'Maximum Sheet Length', '40','Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Wesco'), 'Maximum Sheet Width', '30','Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - Wesco'), 'Run Speed', '21000','inches per hour');

INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue) values ((SELECT lngindex from tbl_equipment where strname='Laminator - GBC Voyager'), 'Laminating Capable', 'Y');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue) values ((SELECT lngindex from tbl_equipment where strname='Laminator - GBC Voyager'), 'Laminating Sides', 'Single');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue) values ((SELECT lngindex from tbl_equipment where strname='Laminator - GBC Voyager'), 'Laminating Style', 'Sheet');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue,strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - GBC Voyage'), 'Laminate Width', '29.5', 'Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue,strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - GBC Voyager'), 'Laminating Count', 'Net Sheets', '');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue,strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - GBC Voyager'), 'Laminating Waste', '10', 'Percent');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - GBC Voyager'), 'Maximum Calliper', '0.018','Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - GBC Voyager'), 'Minimum Calliper', '0.008','Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - GBC Voyager'), 'Minimum Sheet Length', '12','Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - GBC Voyager'), 'Minimum Sheet Width', '12','Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - GBC Voyager'), 'Maximum Sheet Length', '40','Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - GBC Voyager'), 'Maximum Sheet Width', '30','Inches');
INSERT INTO tbl_equipment_specifications (lngequipmentindex,strname,strvalue, strunits) values ((SELECT lngindex from tbl_equipment where strname='Laminator - GBC Voyager'), 'Run Speed', '72000','inches per hour');

