
alter table tbl_project_contents add column price_override decimal(10,2);

alter table ship_address add column price decimal(10,2);
alter table ship_address add qty int;
