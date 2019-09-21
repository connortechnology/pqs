DROP table packing_slip;
create table packing_slip (
	id serial primary key,
	pid  int,
	boxes int,
	item_qty int,
	notes text,
	pack_date date
);
