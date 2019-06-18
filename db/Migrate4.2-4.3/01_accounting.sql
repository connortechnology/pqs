


drop table bill_category cascade;
drop table bills;



create table bill_category (
	id SERIAL PRIMARY KEY,
	name text
);

create table bills (
	id SERIAL PRIMARY KEY,
	category int REFERENCES bill_category(id) ON DELETE CASCADE,
	company int,
	billdate date,
	duedate	date,
	amount numeric(10,2),
	description text
);


create table bill_pay_methods (
	id SERIAL PRIMARY KEY,
	name text
);

create table bill_payments (
	id serial primary key,
	bill int references bills(id) on delete CASCADE,
	userid int references tbl_customer_users(lnguserid) on delete CASCADE,
	amount numeric(10,2),
	payment_type int references bill_pay_methods(id) on delete CASCADE,
	description text

);


INSERT into bill_category (name) values ( 'Test 1');
INSERT into bill_category (name) values ( 'Test 2');
