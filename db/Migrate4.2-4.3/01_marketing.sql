create sequence promo_seq;



drop table promo;
create table promo (
	id int DEFAULT nextval(('promo_seq')),
	name text,
	title text,
	description text,
	projectType int,
	productCategory int,
	startdate timestamp,
	enddate timestamp,
	minspend numeric(10,2),
	percentDiscount numeric(4,2),
	maxDollar numeric(10,2)

);

Create table marketing_promo (
	marketing int,
	promo int
);


ALTER TABLE ONLY promo ADD CONSTRAINT promo_pkey PRIMARY KEY (id);


Create table order_discount (
	promo int,
	customer int,
	orderid int,
	contentid int,
	discount numeric(10,2),
	complete bool
);

alter table tbl_order_contents add column discount numeric(10,2);

