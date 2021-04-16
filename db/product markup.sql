
create sequence markup_cat_seq;
drop table markup_group;
create table markup_group (
	id  Serial primary key,
	name text
);


CREATE table group_markups (
	mugroup int,
	category int,
	markup int
);


alter table tbl_customer add column markup_group int;

